import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Loads only the selected server's verification page. Credentials and session
/// tokens never enter the WebView; it returns a single-use challenge token.
class LoginChallenge extends StatefulWidget {
  const LoginChallenge({required this.url, super.key});

  final Uri url;

  @override
  State<LoginChallenge> createState() => _LoginChallengeState();
}

class _LoginChallengeState extends State<LoginChallenge> {
  late final WebViewController controller;
  Timer? timeout;
  String? error;
  bool finished = false;

  @override
  void initState() {
    super.initState();
    controller = WebViewController();
    unawaited(load());
  }

  Future<void> load() async {
    timeout = Timer(const Duration(minutes: 3), fail);
    try {
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.addJavaScriptChannel(
        'GreenhouseTurnstile',
        onMessageReceived: (message) {
          if (!mounted ||
              finished ||
              error != null ||
              ModalRoute.of(context)?.isCurrent != true) {
            return;
          }
          try {
            final data = jsonDecode(message.message);
            final token = data is Map ? data['token'] : null;
            if (token is! String ||
                token.trim().isEmpty ||
                token.length > 2048) {
              fail();
              return;
            }
            finished = true;
            timeout?.cancel();
            Navigator.of(context).pop(token);
          } on FormatException {
            fail();
          }
        },
      );
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            // Cloudflare needs its challenge frames and about: documents.
            // Keep the top-level page on this installation's exact URL.
            if (!request.isMainFrame) return NavigationDecision.navigate;
            return Uri.tryParse(request.url) == widget.url
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == true) fail();
          },
          onHttpError: (error) {
            if (error.request?.uri == widget.url) fail();
          },
        ),
      );
      if (mounted) await controller.loadRequest(widget.url);
    } catch (_) {
      fail();
    }
  }

  void fail() {
    if (!mounted || finished) return;
    timeout?.cancel();
    setState(
      () => error =
          'Verification could not finish. Go back and try signing in again.',
    );
  }

  @override
  void dispose() {
    timeout?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Verify sign-in')),
    body: SafeArea(
      child: error == null
          ? WebViewWidget(controller: controller)
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Text(error!, semanticsLabel: error),
            ),
    ),
  );
}
