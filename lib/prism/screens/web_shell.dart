import '../diag.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui show FlutterView;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../net/link_gauge.dart';
import '../net/local_vault.dart';
import '../net/push_gate.dart';
import '../net/ua_forger.dart';
import '../net/web_injectors.dart';
import '../settings.dart';
import 'no_link_screen.dart';

// в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
// WEB SHELL вЂ” WebView host for the gray target
// в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
// Hosts the target URL with:
//   вЂў forged device UA identical to the HTTP client's
//   вЂў both orientations, immersive system UI
//   вЂў external-scheme hand-off (tel:, mailto:, intent://)
//   вЂў redirect-loop recovery (main-frame -1007 / -9)
//   вЂў live connectivity guard (debounced)
//   вЂў warm push URL delivery via [PushGate.onWarmUrl]
//   вЂў native file chooser via MethodChannel (no file_picker dep)
//   вЂў JS enhancers composed by [WebInjectors.installAll]
//   вЂў first-hop redirects stay in-frame (window.open / _blank)
//
// NO client-side classification of the target site вЂ” no
// keyword regexes over the page content. Any classification
// needed by the business lives server side; the client is a
// dumb shell.
// в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ

class WebShell extends StatefulWidget {
  const WebShell({
    super.key,
    required this.url,
    required this.vault,
    required this.pushGate,
  });

  final String url;
  final LocalVault vault;
  final PushGate pushGate;

  @override
  State<WebShell> createState() => _WebShellState();
}

class _WebShellState extends State<WebShell>
    with WidgetsBindingObserver {
  late final WebViewController _wv;
  bool _spinner = true;
  bool _offlineShown = false;
  String? _lastMainFrame;
  int _redirectRetries = 0;
  int _hopTick = 0;
  Timer? _dropTimer;
  Timer? _loadWatchdog;
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  // Watchdog window: on some Android WebView builds, a request
  // against a dead network just hangs the main frame вЂ” no
  // onWebResourceError, no onPageFinished вЂ” leaving the user on
  // a frozen spinner. If we don't see onPageFinished within this
  // window, we probe connectivity and route offline if there is
  // truly no reach. 15 s is comfortably above a cold TLS + first
  // paint on a slow 3G, but below a reasonable patience window.
  static const Duration _loadWatchdogWindow = Duration(seconds: 15);

  // Towerbound glass_deck: cache the max safe area seen per
  // orientation and reapply that one box when the phone turns.
  EdgeInsets _padPortrait = EdgeInsets.zero;
  EdgeInsets _padLandscape = EdgeInsets.zero;

  // Rotate per project. Same string in MainActivity.kt.
  static const MethodChannel _uploadBridge =
      MethodChannel('lumina.prism/upload_bridge');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _enterImmersive();
    _assembleController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_setImeOverlay(true));
      unawaited(_bootLoad());
    });

    widget.pushGate.onWarmUrl = (String url) {
      if (mounted) _wv.loadRequest(Uri.parse(url));
    };

    // Debounce connectivity drops вЂ” a VPN reconnect or a brief
    // cell switch produces a burst of `none` events that must
    // not route the user out. Only sustained drops route out
    // (pitfalls В§3).
    _connSub = LinkGauge().changes.listen(
      (List<ConnectivityResult> r) {
        final bool allNone = r.isNotEmpty &&
            r.every((e) => e == ConnectivityResult.none);
        if (!allNone) {
          _dropTimer?.cancel();
          _dropTimer = null;
          return;
        }
        _dropTimer?.cancel();
        _dropTimer = Timer(
          const Duration(milliseconds: PrismSettings.dropDebounceMs),
          _routeOffline,
        );
      },
    );
  }

  Future<void> _setImeOverlay(bool on) async {
    try {
      await _uploadBridge.invokeMethod<void>(
        'ime_overlay',
        <String, Object>{'on': on},
      );
    } catch (_) {}
  }

  void _enterImmersive() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: const <SystemUiOverlay>[],
    );
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarContrastEnforced: false,
    ));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _enterImmersive();
  }

  // Rotation on many Android ROMs (ColorOS, MIUI, some OneUI
  // builds) drops immersiveSticky and re-shows the system nav
  // bar as a black strip at the bottom of the landscape view.
  // Re-applying the mode on every metrics change keeps the
  // WebView flush with the physical edges after a turn.
  Orientation? _lastOrientation;
  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    final ui.FlutterView? view =
        WidgetsBinding.instance.platformDispatcher.implicitView;
    if (view == null) return;
    final Size logical = view.physicalSize / view.devicePixelRatio;
    final Orientation next = logical.width >= logical.height
        ? Orientation.landscape
        : Orientation.portrait;
    if (_lastOrientation == next) return;
    _lastOrientation = next;
    _enterImmersive();
    // A second pass after the OS has finished the rotation
    // animation вЂ” some devices restore the nav bar mid-animation.
    Future<void>.delayed(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      _enterImmersive();
    });
  }

  void _assembleController() {
    _wv = WebViewController();
    unawaited(_wv.setJavaScriptMode(JavaScriptMode.unrestricted));
    unawaited(_wv.setUserAgent(UaForger.value));
    unawaited(_wv.setBackgroundColor(Colors.black));
    unawaited(_wv.enableZoom(false));
    unawaited(_wv.setNavigationDelegate(NavigationDelegate(
      onPageStarted: (String url) {
        _hopTick = 0;
        if (_isHttpish(url)) _lastMainFrame = url;
        if (mounted) setState(() => _spinner = true);
        _armLoadWatchdog();
        unawaited(WebInjectors.installHop(_wv));
      },
      onProgress: (int p) {
        if (p >= 12 && _hopTick < 2) {
          _hopTick++;
          unawaited(WebInjectors.installHop(_wv));
        }
        // Any meaningful progress в†’ page is responsive, cancel
        // the no-signal watchdog. onPageFinished will land on
        // its own.
        if (p >= 60) _cancelLoadWatchdog();
      },
      onPageFinished: (_) {
        if (mounted) setState(() => _spinner = false);
        _redirectRetries = 0;
        _cancelLoadWatchdog();
        unawaited(WebInjectors.installAll(_wv));
      },
      onUrlChange: (UrlChange change) {
        final String? next = change.url;
        if (next != null && _isHttpish(next)) _lastMainFrame = next;
      },
      onWebResourceError: _onError,
      onNavigationRequest: _decideNavigation,
    )));
  }

  void _armLoadWatchdog() {
    _loadWatchdog?.cancel();
    _loadWatchdog = Timer(_loadWatchdogWindow, _loadWatchdogFired);
  }

  void _cancelLoadWatchdog() {
    _loadWatchdog?.cancel();
    _loadWatchdog = null;
  }

  Future<void> _loadWatchdogFired() async {
    plog(() => '[LF/WEB] watchdog fired вЂ” probing connectivity');
    if (_offlineShown || !mounted) return;
    final bool reachable = await LinkGauge()
        .canReach()
        .timeout(const Duration(seconds: 6), onTimeout: () => false);
    plog(() => '[LF/WEB] watchdog reachable=$reachable');
    if (!reachable && mounted) {
      _routeOffline();
    } else if (reachable && mounted) {
      // Page silently stalled while connectivity is actually up вЂ”
      // single reload of the last known good URL. Prevents the
      // "stuck spinner forever" trap seen on some WebView builds.
      final String target = _lastMainFrame ?? widget.url;
      plog(() => '[LF/WEB] watchdog soft-reload $target');
      unawaited(_wv.loadRequest(Uri.parse(target)));
      _armLoadWatchdog();
    }
  }

  Future<void> _bootLoad() async {
    await _wv.setJavaScriptMode(JavaScriptMode.unrestricted);
    await _wv.setUserAgent(UaForger.value);
    await _configureAndroid();
    if (!mounted) return;
    _armLoadWatchdog();
    await _wv.loadRequest(Uri.parse(widget.url));
  }

  bool _isHttpish(String url) {
    final String lower = url.toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  void _onError(WebResourceError err) {
    if (err.isForMainFrame != true) return;

    final String desc = err.description.toLowerCase();
    final bool isLoop = desc.contains('too_many_redirects') ||
        desc.contains('too many redirects') ||
        err.errorCode == -1007 ||
        err.errorCode == -9;

    if (isLoop &&
        _lastMainFrame != null &&
        _redirectRetries < PrismSettings.redirectRetryBudget) {
      _redirectRetries++;
      _wv.loadRequest(Uri.parse(_lastMainFrame!));
      return;
    }

    // Cover the WebView's native error page immediately so the
    // Android chrome robot never leaks (pitfalls В§4).
    if (mounted) setState(() => _spinner = true);

    final bool dnsOrDisc = desc.contains('name_not_resolved') ||
        desc.contains('address_unreachable') ||
        desc.contains('internet_disconnected') ||
        desc.contains('network_changed') ||
        err.errorCode == -105 ||
        err.errorCode == -106 ||
        err.errorCode == -21 ||
        err.errorCode == -2 ||
        err.errorCode == -6;

    if (dnsOrDisc) {
      _routeOffline();
    } else {
      _softGuardOffline();
    }
  }

  NavigationDecision _decideNavigation(NavigationRequest req) {
    final Uri? uri = Uri.tryParse(req.url);
    if (uri == null) return NavigationDecision.navigate;
    final String scheme = uri.scheme.toLowerCase();
    const Set<String> inApp = <String>{
      'http',
      'https',
      'about',
      'data',
      'blob',
      'javascript',
    };
    if (scheme.isEmpty || inApp.contains(scheme)) {
      if (req.isMainFrame && (scheme == 'http' || scheme == 'https')) {
        _lastMainFrame = req.url;
      }
      return NavigationDecision.navigate;
    }
    _handOff(uri);
    return NavigationDecision.prevent;
  }

  Future<void> _configureAndroid() async {
    if (!Platform.isAndroid) return;
    if (_wv.platform is! AndroidWebViewController) return;
    final AndroidWebViewController ctrl =
        _wv.platform as AndroidWebViewController;

    await ctrl.setMediaPlaybackRequiresUserGesture(false);
    await ctrl.setUseWideViewPort(true);
    await ctrl.setMixedContentMode(MixedContentMode.alwaysAllow);
    await ctrl.setGeolocationEnabled(true);
    await ctrl.setGeolocationPermissionsPromptCallbacks(
      onShowPrompt: (_) async {
        return const GeolocationPermissionsResponse(
          allow: true,
          retain: true,
        );
      },
    );
    await ctrl.setOnPlatformPermissionRequest(
      (PlatformWebViewPermissionRequest r) => r.grant(),
    );
    await ctrl.setOnShowFileSelector(_pickFiles);

    final AndroidWebViewCookieManager cookies =
        AndroidWebViewCookieManager(
      AndroidWebViewCookieManagerCreationParams
          .fromPlatformWebViewCookieManagerCreationParams(
        const PlatformWebViewCookieManagerCreationParams(),
      ),
    );
    await cookies.setAcceptThirdPartyCookies(ctrl, true);

    final Map<String, Object> tuneArgs = <String, Object>{
      'id': ctrl.webViewIdentifier,
    };
    for (int i = 0; i < 3; i++) {
      try {
        final bool? ok =
            await _uploadBridge.invokeMethod<bool>('tune_webview', tuneArgs);
        if (ok == true) break;
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
  }

  Future<List<String>> _pickFiles(FileSelectorParams params) async {
    try {
      final List<Object?>? picked = await _uploadBridge
          .invokeMethod<List<Object?>>('open', <String, Object>{
        'multi': params.mode == FileSelectorMode.openMultiple,
        'mimes': params.acceptTypes
            .where((String t) => t.trim().isNotEmpty)
            .toList(),
      });
      if (picked == null) return const <String>[];
      return picked.whereType<String>().toList();
    } catch (_) {
      return const <String>[];
    }
  }

  Future<void> _handOff(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _softGuardOffline() async {
    if (_offlineShown) return;
    final bool online = await LinkGauge().canReach();
    if (online) return;
    _routeOffline();
  }

  void _routeOffline() {
    if (_offlineShown || !mounted) return;
    _offlineShown = true;
    final String snapshot = _lastMainFrame ?? widget.url;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => NoLinkScreen(
          rebuildRoute: (_) => WebShell(
            url: snapshot,
            vault: widget.vault,
            pushGate: widget.pushGate,
          ),
        ),
      ),
    );
  }

  Future<void> _stepBack() async {
    if (await _wv.canGoBack()) await _wv.goBack();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dropTimer?.cancel();
    _loadWatchdog?.cancel();
    _connSub?.cancel();
    unawaited(_setImeOverlay(false));
    widget.pushGate.onWarmUrl = null;
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: const <SystemUiOverlay>[],
    );
    super.dispose();
  }

  EdgeInsets _safePad(MediaQueryData mq) {
    final EdgeInsets vp = mq.viewPadding;
    final bool land = mq.orientation == Orientation.landscape;
    // Same policy as Towerbound (glass_deck / StreamPortal):
    //   portrait  в†’ top safe-area only (camera notch).
    //   landscape в†’ left + right safe-area only.
    // Bottom stays 0. Intermediate inset frames are ignored by
    // keeping the max value already seen for this orientation.
    if (land) {
      _padLandscape = EdgeInsets.only(
        left: math.max(_padLandscape.left, vp.left),
        right: math.max(_padLandscape.right, vp.right),
      );
    } else {
      _padPortrait = EdgeInsets.only(
        top: math.max(_padPortrait.top, vp.top),
      );
    }
    return land ? _padLandscape : _padPortrait;
  }

  @override
  Widget build(BuildContext context) {
    final MediaQueryData mq = MediaQuery.of(context);
    final EdgeInsets pad = _safePad(mq);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, _) async {
        if (!didPop) await _stepBack();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false,
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            const ColoredBox(color: Colors.black),
            Padding(
              padding: pad,
              child: RepaintBoundary(
                child: WebViewWidget(controller: _wv),
              ),
            ),
            if (_spinner)
              const ColoredBox(
                color: Color(0x66000000),
                child: Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFFF5C542),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
