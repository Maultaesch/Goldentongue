import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/data_providers.dart';
import '../../widgets/common.dart';
import '../studio/charts.dart';

typedef SkillPoint = (DateTime, int);

const _skills = <(String, String)>[
  ('confidence', 'Confidence'),
  ('communication', 'Communication'),
  ('flirting', 'Flirting'),
  ('deep_talk', 'Deep Talk'),
  ('articulation', 'Articulation'),
  ('charisma', 'Charisma'),
  ('business', 'Business'),
];

/// Score history for the last 90 days, oldest first, grouped by skill.
final skillHistoryProvider = FutureProvider.autoDispose<Map<String, List<SkillPoint>>>((ref) async {
  final from = DateTime.now().subtract(const Duration(days: 90)).toUtc().toIso8601String();
  final rows = await sb
      .from('skill_scores')
      .select('skill,score,measured_at')
      .eq('user_id', uid)
      .gte('measured_at', from)
      .order('measured_at');
  final out = <String, List<SkillPoint>>{};
  for (final r in rows) {
    (out[r['skill'] as String] ??= []).add((DateTime.parse(r['measured_at'] as String).toLocal(), (r['score'] as num).toInt()));
  }
  return out;
});

/// Completed daily challenges per day for the last 7 days (oldest first).
final weeklyActivityProvider = FutureProvider.autoDispose<List<int>>((ref) async {
  final today = DateTime.now();
  final from = today.subtract(const Duration(days: 6)).toIso8601String().substring(0, 10);
  final rows = await sb.from('user_challenges').select('day').eq('user_id', uid).gte('day', from);
  final counts = <String, int>{};
  for (final r in rows) {
    counts.update(r['day'] as String, (v) => v + 1, ifAbsent: () => 1);
  }
  return [
    for (var i = 6; i >= 0; i--)
      counts[today.subtract(Duration(days: i)).toIso8601String().substring(0, 10)] ?? 0,
  ];
});

/// Change versus the score about a week ago (or the first score if the history is shorter).
int? weeklyDelta(List<SkillPoint> history, {DateTime? now}) {
  if (history.length < 2) return null;
  final cutoff = (now ?? DateTime.now()).subtract(const Duration(days: 7));
  var base = history.first.$2;
  for (final p in history) {
    if (p.$1.isAfter(cutoff)) break;
    base = p.$2;
  }
  return history.last.$2 - base;
}

class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final history = ref.watch(skillHistoryProvider);
    final activity = ref.watch(weeklyActivityProvider).valueOrNull ?? List.filled(7, 0);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.black,
        title: Text('Progress', style: t.titleLarge?.copyWith(color: AppColors.gold)),
      ),
      body: SafeArea(
        child: history.when(
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.gold)),
          error: (_, __) => const Center(child: Text('Could not load your progress.')),
          data: (data) {
            int? latest(String k) => data[k]?.last.$2;
            final known = [for (final s in _skills) if (latest(s.$1) != null) latest(s.$1)!];
            final overall = known.isEmpty ? 0 : (known.reduce((a, b) => a + b) / known.length).round();
            return ListView(padding: const EdgeInsets.all(AppSpacing.l), children: [
              AppCard(
                hero: true,
                child: Column(children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                    ScoreRing(value: overall, label: 'Overall'),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: AppSpacing.l),
                        child: Text(
                          known.isEmpty
                              ? 'Complete a daily challenge, a voice analysis or a simulator session to start your dashboard.'
                              : 'Average of ${known.length} of 7 skills with data. Scores blend new results with earlier ones.',
                          style: t.bodySmall,
                        ),
                      ),
                    ),
                  ]),
                  if (known.length >= 3) ...[
                    const SizedBox(height: AppSpacing.m),
                    RadarChart(
                      labels: [for (final s in _skills) s.$2],
                      values: [for (final s in _skills) latest(s.$1) ?? 0],
                    ),
                  ],
                ]),
              ),
              const SizedBox(height: AppSpacing.m),
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Challenges this week', style: t.titleLarge),
                  const SizedBox(height: AppSpacing.m),
                  SizedBox(
                    height: 70,
                    child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      for (final c in activity)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Container(
                              height: 8.0 + c * 40,
                              decoration: BoxDecoration(
                                gradient: c > 0 ? AppColors.goldGradient : null,
                                color: c > 0 ? null : const Color(0xFF2A2A2A),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: AppSpacing.l),
              Text('Skills', style: t.headlineMedium),
              const SizedBox(height: AppSpacing.m),
              for (final s in _skills) ...[
                _SkillCard(label: s.$2, history: data[s.$1] ?? const []),
                const SizedBox(height: AppSpacing.m),
              ],
            ]);
          },
        ),
      ),
    );
  }
}

class _SkillCard extends StatelessWidget {
  final String label;
  final List<SkillPoint> history;
  const _SkillCard({required this.label, required this.history});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final current = history.isEmpty ? null : history.last.$2;
    final delta = weeklyDelta(history);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
          if (delta != null)
            Text(
              delta == 0 ? 'no change this week' : '${delta > 0 ? '+' : ''}$delta this week',
              style: TextStyle(
                fontSize: 12,
                color: delta > 0 ? AppColors.success : (delta < 0 ? const Color(0xFFE0A96D) : AppColors.textSecondary),
              ),
            ),
        ]),
        Text(current?.toString() ?? '–', style: t.displayMedium),
        const SizedBox(height: AppSpacing.s),
        if (history.length >= 2)
          SizedBox(height: 48, width: double.infinity, child: CustomPaint(painter: _Spark(history)))
        else
          Text(current == null ? 'No data yet.' : 'Keep practicing to see a trend.', style: t.bodySmall),
      ]),
    );
  }
}

class _Spark extends CustomPainter {
  final List<SkillPoint> points;
  _Spark(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final n = points.length;
    Offset at(int i) => Offset(
          n == 1 ? 0 : i * size.width / (n - 1),
          size.height - 4 - (size.height - 8) * points[i].$2 / 100,
        );
    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < n; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..color = AppColors.goldPremium,
    );
    canvas.drawCircle(at(n - 1), 4, Paint()..color = AppColors.goldPremium);
  }

  @override
  bool shouldRepaint(covariant _Spark old) => old.points != points;
}
