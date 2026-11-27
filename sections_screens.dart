import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/data_providers.dart';
import '../../widgets/common.dart';

class SectionItem {
  final String title;
  final List<String> tags;
  final String detailLabel;
  final List<String> details;
  final String? route;
  const SectionItem(this.title, this.tags, this.detailLabel, this.details, [this.route]);

  factory SectionItem.fromRow(Map<String, dynamic> r) => SectionItem(
        '${r['title']}',
        [for (final t in (r['tags'] as List? ?? const [])) '$t'],
        '${r['detail_label'] ?? ''}',
        [for (final d in (r['details'] as List? ?? const [])) '$d'],
        r['route'] as String?,
      );
}

/// Section cards come from the database (members only), never from the app code.
final sectionsProvider = FutureProvider.autoDispose.family<List<SectionItem>, String>((ref, track) async {
  final rows = await sb.from('sections').select().eq('track', track).order('position');
  return [for (final r in rows) SectionItem.fromRow(Map<String, dynamic>.from(r))];
});

class _SectionPage extends ConsumerWidget {
  final String track;
  final String title;
  final String intro;
  final String? practiceTrack;
  final Widget? header;
  const _SectionPage({required this.track, required this.title, required this.intro, this.practiceTrack, this.header});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(sectionsProvider(track)).when(
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.gold)),
          error: (_, __) => const Center(child: Text('Could not load this section.')),
          data: (items) => _SectionList(title: title, intro: intro, items: items, header: header, track: practiceTrack),
        );
  }
}

class _SectionList extends StatelessWidget {
  final String title;
  final String intro;
  final List<SectionItem> items;
  final Widget? header;
  final String? track; // 'deep_talk' or 'business': shows a Practice button per category
  const _SectionList({required this.title, required this.intro, required this.items, this.header, this.track});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.l),
      children: [
        Text(title, style: t.headlineLarge),
        const SizedBox(height: AppSpacing.s),
        Text(intro, style: t.bodySmall),
        if (header != null) ...[const SizedBox(height: AppSpacing.l), header!],
        const SizedBox(height: AppSpacing.l),
        for (final item in items) ...[
          Card(
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.all(AppSpacing.l),
                childrenPadding: const EdgeInsets.fromLTRB(AppSpacing.l, 0, AppSpacing.l, AppSpacing.l),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                title: Text(item.title, style: t.titleLarge),
                subtitle: Wrap(children: [for (final tag in item.tags) TagChip(tag)]),
                children: [
                  Container(
                    padding: const EdgeInsets.only(left: AppSpacing.m),
                    decoration: const BoxDecoration(
                      border: Border(left: BorderSide(color: AppColors.gold, width: 2)),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(item.detailLabel, style: t.bodySmall),
                      for (final d in item.details)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.s),
                          child: Text(d),
                        ),
                      if (item.route != null) ...[
                        const SizedBox(height: AppSpacing.m),
                        GoldButton(label: 'Open', onPressed: () => context.push(item.route!)),
                      ],
                      if (track != null) ...[
                        const SizedBox(height: AppSpacing.m),
                        GoldButton(
                          label: 'Practice',
                          onPressed: () => context.push('/practice', extra: <String, String>{'track': track!, 'category': item.title}),
                        ),
                      ],
                    ]),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.m),
        ],
      ],
    );
  }
}

class DeepTalkScreen extends StatelessWidget {
  const DeepTalkScreen({super.key});

  @override
  Widget build(BuildContext context) => const _SectionPage(
        track: 'deep_talk',
        title: 'Deep Talk',
        intro: 'Use these once you both feel comfortable. Listen more than you speak.',
        practiceTrack: 'deep_talk',
      );
}

class BusinessScreen extends StatelessWidget {
  const BusinessScreen({super.key});

  @override
  Widget build(BuildContext context) => const _SectionPage(
        track: 'business',
        title: 'Business',
        intro: 'Open an area for instant coaching, then practice and get scored.',
        practiceTrack: 'business',
      );
}

class SpeakBetterScreen extends ConsumerWidget {
  const SpeakBetterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scores = ref.watch(skillScoresProvider).valueOrNull ?? const <String, int>{};
    return _SectionPage(
      track: 'speak',
      title: 'Speak Better',
      intro: 'Train your voice like a muscle. Ten minutes a day is enough.',
      header: ScoreCard(label: 'Articulation score', score: scores['articulation'] ?? 40),
    );
  }
}
