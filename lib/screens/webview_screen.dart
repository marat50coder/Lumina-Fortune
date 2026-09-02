import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/audio.dart';
import '../core/theme.dart';
import '../widgets/ui.dart';

class WebPageScreen extends StatefulWidget {
  const WebPageScreen({super.key, required this.title, required this.url});
  final String title;
  final String url;

  @override
  State<WebPageScreen> createState() => _WebPageScreenState();
}

class _WebPageScreenState extends State<WebPageScreen> {
  late final WebViewController _c;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    hideChrome();
    lockPortrait();
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFFFFFFF))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p / 100);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Lf.deep,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
              child: Row(
                children: [
                  RoundIconBtn(
                    icon: Icons.arrow_back,
                    onTap: () {
                      AudioHub.I.close();
                      Navigator.pop(context);
                    },
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: TitleBanner(widget.title, size: 22)),
                ],
              ),
            ),
            if (_progress < 1)
              LinearProgressIndicator(
                value: _progress == 0 ? null : _progress,
                minHeight: 3,
                color: Lf.gold,
                backgroundColor: Colors.white10,
              ),
            Expanded(child: WebViewWidget(controller: _c)),
          ],
        ),
      ),
    );
  }
}
