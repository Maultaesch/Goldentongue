import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/data_providers.dart';
import '../../core/ranks.dart';
import '../../widgets/common.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  void _refresh(WidgetRef ref) {
    ref.invalidate(gamificationProvider);
    ref.invalidate(skillScoresProvider);
    ref.invalidate(todayDoneProvider);
    ref.invalidate(completionsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final game = ref.watch(gamificationProvider).valueOrNull ?? const {'xp': 0, 'streak': 0};
    final scores = ref.watch(skillScoresProvider).valueOrNull ?? const <String, int>{};
    final challenge = ref.watch(dailyChallengeProvider).valueOrNull;
    final done = ref.watch(todayDoneProvider).valueOrNull ?? false;

    final xp = (game['xp'] as int?) ?? 0;
    final streak = (game['streak'] as int?) ?? 0;
    final rankIdx = rankIndexFor(xp);
    final next = rankIdx + 1 < ranks.length ? ranks[rankIdx + 1] : null;
    int score(String k) => scores[k] ?? 40;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.l),
      children: [
        Text('Welcome back', style: t.bodySmall),
        Text('Master your presence.', style: t.headlineLarge),
        const SizedBox(height: AppSpacing.xl),
        AppCard(
          hero: true,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("Today's challenge", style: t.bodySmall),
            const SizedBox(height: AppSpacing.s),
            Text(challenge?['text'] as String? ?? 'No challenge available yet.',
                style: t.titleLarge),
            const SizedBox(height: AppSpacing.l),
            if (challenge == null)
              const SizedBox.shrink()
            else if (done)
              const Text('Completed. Come back tomorrow.',
                  style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w700))
            else
              Row(children: [
                for (final (label, value) in [('Smooth', 3), ('Okay', 2), ('Tough', 1)])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.s),
                      child: GoldButton(
                        label: label,
                        onPressed: () async {
                          await completeChallenge(challenge['id'] as String, value);
                          _refresh(ref);
                        },
                      ),
                    ),
                  ),
              ]),
          ]),
        ),
        const SizedBox(height: AppSpacing.m),
        Row(children: [
          Expanded(child: ScoreCard(label: 'Confidence score', score: score('confidence'))),
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Streak', style: t.bodySmall),
                const SizedBox(height: 4),
                Text('$streak', style: t.displayMedium),
                Text('days', style: t.bodySmall),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: AppSpacing.m),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Level', style: t.bodySmall),
            Text(ranks[rankIdx].name, style: t.titleLarge?.copyWith(color: AppColors.goldPremium)),
            const SizedBox(height: AppSpacing.s),
            GoldProgress(value: rankProgress(xp)),
            const SizedBox(height: AppSpacing.s),
            Text(next == null ? '$xp XP' : '$xp XP  ·  next: ${next.name} at ${next.minXp}',
                style: t.bodySmall),
          ]),
        ),
        const SizedBox(height: AppSpacing.m),
        GoldButton(label: 'Quick start AI Coach', onPressed: () => context.push('/coach')),
        const SizedBox(height: AppSpacing.xl),
        Text('Studio', style: t.headlineMedium),
        const SizedBox(height: AppSpacing.m),
        for (final (route, title, sub) in const [
          ('/studio/voice', 'Voice Attraction Analyzer', 'Record 60 seconds and get your voice profile'),
          ('/studio/simulator', 'Conversation Simulator', 'Practice with six realistic characters'),
          ('/studio/blueprint', 'My Charm Blueprint', 'Your personal plan from your results'),
        ]) ...[
          AppCard(
            onTap: () => context.push(route),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: t.titleLarge?.copyWith(color: AppColors.goldPremium)),
              Text(sub, style: t.bodySmall),
            ]),
          ),
          const SizedBox(height: AppSpacing.m),
        ],
        const SizedBox(height: AppSpacing.xl),
        Row(children: [
          Expanded(child: Text('Your scores', style: t.headlineMedium)),
          TextButton(onPressed: () => context.push('/progress'), child: const Text('Full progress')),
        ]),
        const SizedBox(height: AppSpacing.m),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AppSpacing.m,
          crossAxisSpacing: AppSpacing.m,
          childAspectRatio: 1.25,
          children: [
            ScoreCard(label: 'Communication', score: score('communication')),
            ScoreCard(label: 'Flirting', score: score('flirting')),
            ScoreCard(label: 'Articulation', score: score('articulation')),
            ScoreCard(label: 'Business', score: score('business')),
          ],
        ),
      ],
    );
  }
}
