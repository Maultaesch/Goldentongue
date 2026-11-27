import 'package:cloudflare_turnstile/cloudflare_turnstile.dart';
import 'package:flutter/material.dart';

import '../../core/env.dart';

/// Lets the parent ask for a fresh challenge. A Turnstile token can be used only once,
/// so reset after every sign up or login attempt.
class CaptchaController {
  VoidCallback? _reset;
  void reset() => _reset?.call();
}

/// Cloudflare Turnstile widget. Renders nothing when no site key is configured.
/// Supabase verifies the token on the server (Auth -> Attack Protection -> CAPTCHA).
class TurnstileBox extends StatefulWidget {
  final CaptchaController controller;
  final void Function(String? token) onToken;
  const TurnstileBox({super.key, required this.controller, required this.onToken});

  @override
  State<TurnstileBox> createState() => _TurnstileBoxState();
}

class _TurnstileBoxState extends State<TurnstileBox> {
  final _turnstile = TurnstileController();

  @override
  void initState() {
    super.initState();
    widget.controller._reset = () {
      widget.onToken(null);
      _turnstile.refreshToken();
    };
  }

  @override
  Widget build(BuildContext context) {
    if (!Env.captchaEnabled) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: CloudflareTurnstile(
        siteKey: Env.turnstileSiteKey,
        baseUrl: Env.turnstileBaseUrl,
        controller: _turnstile,
        onTokenReceived: (token) => widget.onToken(token),
        onTokenExpired: () => widget.onToken(null),
        onError: (_) => widget.onToken(null),
      ),
    );
  }
}
