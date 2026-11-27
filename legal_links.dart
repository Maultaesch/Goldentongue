import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/env.dart';

/// Links to the privacy policy and the terms of use (set PRIVACY_URL and TERMS_URL at build time).
class LegalLinks extends StatelessWidget {
  const LegalLinks({super.key});

  Widget _link(String label, String url) => TextButton(
        onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        child: Text(label, style: const TextStyle(fontSize: 12)),
      );

  @override
  Widget build(BuildContext context) {
    if (Env.privacyUrl.isEmpty && Env.termsUrl.isEmpty) return const SizedBox.shrink();
    return Wrap(alignment: WrapAlignment.center, children: [
      if (Env.privacyUrl.isNotEmpty) _link('Privacy policy', Env.privacyUrl),
      if (Env.termsUrl.isNotEmpty) _link('Terms of use', Env.termsUrl),
    ]);
  }
}
