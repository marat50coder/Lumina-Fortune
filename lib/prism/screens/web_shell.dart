import 'dart:async';
import 'dart:io';

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

// ─────────────────────────────────────────────────────────────
// WEB SHELL — WebView host for the gray target
// ─────────────────────────────────────────────────────────────
// Hosts the target URL with:
//   • forged device UA identical to the HTTP client's
//   • both orientations, immersive system UI
//   • external-scheme hand-off (tel:, mailto:, intent://)
//   • redirect-loop recovery (main-frame -1007 / -9)
//   • live connectivity guard (debounced)
//   • warm push URL delivery via [PushGate.onWarmUrl]
//   • native file chooser via MethodChannel (no file_picker dep)
//   • JS enhancers composed by [WebInjectors.installAll]
//
// NO client-side classification of the target site — no
// keyword regexes over the page content. Any classification
// needed by the business lives server side; the client is a
// dumb shell.
// ─────────────────────────────────────────────────────────────

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
  Timer? _dropTimer;
  Timer? _rotateVeilTimer;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  Orientation? _lastOrientation;
  bool _rotating = false;

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
    _mountController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_setImeOverlay(true));
    });

    widget.pushGate.onWarmUrl = (String url) {
      if (mounted) _wv.loadRequest(Uri.parse(url));
    };

    // Debounce connectivity drops — a VPN reconnect or a brief
    // cell switch produces a burst of `none` events that must
    // not route the user out. Only sustained drops route out
    // (pitfalls §3).
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

  void _mountController() {
    _wv = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(UaForger.value)
      ..setBackgroundColor(Colors.black)
      ..enableZoom(false)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() => _spinner = true);
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _spinner = false);
          _redirectRetries = 0;
          WebInjectors.installAll(_wv);
        },
        onWebResourceError: _onError,
        onNavigationRequest: _decideNavigation,
      ));

    _configureAndroid();
    _wv.loadRequest(Uri.parse(widget.url));
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
    // Android chrome robot never leaks (pitfalls §4).
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
    if (uri == null) return NavigationDecision.prevent;
    const Set<String> inApp = <String>{
      'http',
      'https',
      'about',
      'data',
      'blob',
    };
    if (inApp.contains(uri.scheme)) {
      if (req.isMainFrame) _lastMainFrame = req.url;
      return NavigationDecision.navigate;
    }
    _handOff(uri);
    return NavigationDecision.prevent;
  }

  void _configureAndroid() {
    if (!Platform.isAndroid) return;
    if (_wv.platform is! AndroidWebViewController) return;
    final AndroidWebViewController ctrl =
        _wv.platform as AndroidWebViewController;

    ctrl.setMediaPlaybackRequiresUserGesture(false);
    ctrl.setOnPlatformPermissionRequest(
      (PlatformWebViewPermissionRequest r) => r.grant(),
    );
    ctrl.setOnShowFileSelector(_pickFiles);

    final AndroidWebViewCookieManager cookies =
        AndroidWebViewCookieManager(
      AndroidWebViewCookieManagerCreationParams
          .fromPlatformWebViewCookieManagerCreationParams(
        const PlatformWebViewCookieManagerCreationParams(),
      ),
    );
    cookies.setAcceptThirdPartyCookies(ctrl, true);
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
    _rotateVeilTimer?.cancel();
    _connSub?.cancel();
    unawaited(_setImeOverlay(false));
    widget.pushGate.onWarmUrl = null;
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: const <SystemUiOverlay>[],
    );
    super.dispose();
  }

  void _onOrientationChange(Orientation next) {
    if (_lastOrientation == null) {
      _lastOrientation = next;
      return;
    }
    if (_lastOrientation == next) return;
    _lastOrientation = next;
    // The Android WebView surface briefly stretches while it
    // reflows to the new size. Cover the transition with a
    // matching-black veil so the user never sees the smeared
    // frame; drop the veil once the native surface has settled.
    if (mounted) setState(() => _rotating = true);
    _rotateVeilTimer?.cancel();
    _rotateVeilTimer = Timer(const Duration(milliseconds: 320), () {
      if (mounted) setState(() => _rotating = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, _) async {
        if (!didPop) await _stepBack();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false,
        body: OrientationBuilder(
          builder: (BuildContext ctx, Orientation orientation) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _onOrientationChange(orientation);
            });
            // No manual padding — the JS enhancer neutralises the
            // site-side safe-area vars, and SafeArea would just
            // add a second inset that jitters on rotation. The
            // WebView paints edge-to-edge on a black surface, so
            // the native surface never shows a white stretch.
            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                const ColoredBox(color: Colors.black),
                WebViewWidget(controller: _wv),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  opacity: _rotating ? 1.0 : 0.0,
                  child: IgnorePointer(
                    ignoring: !_rotating,
                    child: const ColoredBox(
                      color: Colors.black,
                      child: Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFFF5C542),
                          ),
                        ),
                      ),
                    ),
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
            );
          },
        ),
      ),
    );
  }
}
