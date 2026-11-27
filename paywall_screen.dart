import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show Package;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/access.dart';
import '../../core/data_providers.dart';
import '../../widgets/legal_links.dart';
import '../auth/auth_repository.dart';
import '../../widgets/common.dart';
import 'billing_service.dart';
import 'premium_providers.dart';

const _features = [
  'Unlimited AI coaching',
  'Deep Talk with conversation guides',
  'Voice Analysis and speaking feedback',
  'Business communication training',
  'Conversation Simulator',
  'Personalized plans and analytics',
];

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  final _billing = BillingService.instance;
  BillingPlan _selected = BillingPlan.yearly;
  Map<BillingPlan, Package> _packages = {};
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _billing.packages().then((p) {
      if (mounted) setState(() => _packages = p);
    }).catchError((_) {});
  }

  String _price(BillingPlan plan) =>
      _packages[plan]?.storeProduct.priceString ?? plan.fallbackPrice;

  Future<void> _subscribe() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (kIsWeb) {
        final res = await sb.functions.invoke('create-checkout', body: {'plan': _selected.id});
        final url = (res.data as Map)['url'] as String?;
        if (url == null) throw StateError('No checkout url');
        await launchUrl(Uri.parse(url), webOnlyWindowName: '_self');
        return;
      }
      final package = _packages[_selected];
      if (package == null) {
        setState(() => _message = 'Subscriptions are not available right now. Please try again later.');
        return;
      }
      final purchased = await _billing.purchase(package);
      if (purchased) await _waitForPremium();
    } on FunctionException {
      setState(() => _message = 'Could not start checkout. Please try again.');
    } catch (_) {
      setState(() => _message = 'The purchase could not be completed. You have not been charged.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _billing.restore();
      await _waitForPremium();
    } catch (_) {
      setState(() => _message = 'Could not restore purchases.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The webhook writes the subscription; poll briefly until the server confirms it.
  Future<void> _waitForPremium() async {
    for (var i = 0; i < 10; i++) {
      final ok = await sb.rpc('is_premium_self') == true;
      if (ok) {
        ref.invalidate(isPremiumProvider);
        await ref.read(accessProvider).refresh(); // the router then opens the app
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    if (mounted) {
      setState(() => _message = 'Your purchase is being activated. This can take a minute.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.black,
        automaticallyImplyLeading: false,
        actions: [TextButton(onPressed: () => AuthRepository().signOut(), child: const Text('Sign out'))],
      ),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(AppSpacing.l), children: [
          Text('Membership', style: t.headlineLarge?.copyWith(color: AppColors.gold)),
          const SizedBox(height: AppSpacing.s),
          Text('Create your account, choose a plan and unlock everything: coaching, lines, voice, simulator and practice.', style: t.bodySmall),
          const SizedBox(height: AppSpacing.xl),
          for (final plan in BillingPlan.values) ...[
            AppCard(
              hero: plan == _selected,
              onTap: () => setState(() => _selected = plan),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(plan.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(plan.note, style: t.bodySmall),
                  ]),
                ),
                Text(_price(plan), style: t.titleLarge?.copyWith(color: AppColors.gold)),
              ]),
            ),
            const SizedBox(height: AppSpacing.m),
          ],
          const SizedBox(height: AppSpacing.s),
          for (final f in _features)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                const Icon(Icons.check, size: 18, color: AppColors.gold),
                const SizedBox(width: AppSpacing.m),
                Expanded(child: Text(f)),
              ]),
            ),
          const SizedBox(height: AppSpacing.xl),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.m),
              child: Text(_message!, style: const TextStyle(color: Colors.redAccent)),
            ),
          GoldButton(
            label: 'Continue',
            onPressed: _busy ? null : _subscribe,
          ),
          if (!kIsWeb)
            TextButton(onPressed: _busy ? null : _restore, child: const Text('Restore purchases')),
          const SizedBox(height: AppSpacing.s),
          Text(
            'Subscriptions renew automatically until cancelled. You can manage or cancel '
            'in your store account settings at any time.',
            style: t.bodySmall,
            textAlign: TextAlign.center,
          ),
          const LegalLinks(),
        ]),
      ),
    );
  }
}
