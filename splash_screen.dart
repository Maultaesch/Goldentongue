import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/access.dart';
import '../../widgets/common.dart';
import 'auth_repository.dart';

/// Shown while the membership is being checked right after login.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(accessProvider);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: access.failed
              ? Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('We could not check your membership.', style: t.titleLarge, textAlign: TextAlign.center),
                  const SizedBox(height: AppSpacing.m),
                  Text('Check your connection and try again.', style: t.bodySmall),
                  const SizedBox(height: AppSpacing.l),
                  GoldButton(label: 'Try again', onPressed: () => access.refresh()),
                  TextButton(onPressed: () => AuthRepository().signOut(), child: const Text('Sign out')),
                ])
              : const CircularProgressIndicator(color: AppColors.gold),
        ),
      ),
    );
  }
}
