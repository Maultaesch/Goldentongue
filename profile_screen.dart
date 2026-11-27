import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/data_providers.dart';
import '../../core/ranks.dart';
import '../../widgets/common.dart';
import '../../widgets/legal_links.dart';
import '../auth/auth_repository.dart';
import '../billing/premium_providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final game = ref.watch(gamificationProvider).valueOrNull ?? const {'xp': 0};
    final xp = (game['xp'] as int?) ?? 0;
    final rankIdx = rankIndexFor(xp);
    final week = ref.watch(completionsProvider(7)).valueOrNull ?? 0;
    final month = ref.watch(completionsProvider(30)).valueOrNull ?? 0;
    final premium = ref.watch(isPremiumProvider).valueOrNull ?? false;
    final admin = ref.watch(isAdminProvider).valueOrNull ?? false;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.l),
      children: [
        Text('Profile', style: t.headlineLarge),
        const SizedBox(height: AppSpacing.l),
        AppCard(
          hero: true,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Current rank', style: t.bodySmall),
            Text(ranks[rankIdx].name, style: t.headlineMedium?.copyWith(color: AppColors.goldPremium)),
            Text('$xp XP', style: t.bodySmall),
          ]),
        ),
        const SizedBox(height: AppSpacing.m),
        Row(children: [
          Expanded(child: _Stat(label: 'This week', value: week)),
          const SizedBox(width: AppSpacing.m),
          Expanded(child: _Stat(label: 'This month', value: month)),
        ]),
        const SizedBox(height: AppSpacing.m),
        if (admin)
          const AppCard(child: Row(children: [
            Icon(Icons.verified, color: AppColors.goldPremium),
            SizedBox(width: AppSpacing.m),
            Text('Admin · unlimited access', style: TextStyle(fontWeight: FontWeight.w700)),
          ]))
        else if (premium)
          const AppCard(child: Row(children: [
            Icon(Icons.workspace_premium, color: AppColors.goldPremium),
            SizedBox(width: AppSpacing.m),
            Text('Premium member', style: TextStyle(fontWeight: FontWeight.w700)),
          ]))
        else
          GoldButton(label: 'Upgrade to Premium', onPressed: () => context.push('/paywall')),
        const SizedBox(height: AppSpacing.xl),
        Text('Badges', style: t.headlineMedium),
        const SizedBox(height: AppSpacing.m),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AppSpacing.m,
          crossAxisSpacing: AppSpacing.m,
          childAspectRatio: 2.2,
          children: [
            for (var i = 0; i < ranks.length; i++)
              Opacity(
                opacity: i <= rankIdx ? 1 : 0.35,
                child: AppCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(ranks[i].name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('${ranks[i].minXp} XP', style: t.bodySmall),
                  ]),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        OutlinedButton(onPressed: () => AuthRepository().signOut(), child: const Text('Sign out')),
        const SizedBox(height: AppSpacing.m),
        TextButton(
          onPressed: () => _deleteAccount(context),
          child: const Text('Delete account', style: TextStyle(color: Colors.redAccent)),
        ),
        const LegalLinks(),
      ],
    );
  }
}

Future<void> _deleteAccount(BuildContext context) async {
  final controller = TextEditingController();
  final messenger = ScaffoldMessenger.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete your account?'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('This permanently deletes your account and all your data. It cannot be undone.'),
        const SizedBox(height: 12),
        const Text(
          'A subscription is not cancelled automatically. Cancel it in your App Store, Google Play or Stripe account, otherwise it keeps renewing.',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 12),
        TextField(controller: controller, decoration: const InputDecoration(labelText: 'Type DELETE to confirm')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, controller.text.trim() == 'DELETE'),
          child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
        ),
      ],
    ),
  );
  controller.dispose();
  if (confirmed != true) return;
  try {
    await AuthRepository().deleteAccount();
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('The account could not be deleted. Please try again or contact support.')));
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final int value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: t.bodySmall),
        Text('$value', style: t.displayMedium),
      ]),
    );
  }
}
