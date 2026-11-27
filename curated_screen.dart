import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/data_providers.dart';
import '../../widgets/common.dart';
import '../social/social_screen.dart' show favoritesProvider;

/// Curated lists stored in `lines`: collection 'opener' (50 openers) and 'flirt' (50 techniques).
final curatedProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, collection) async {
  final rows = await sb.from('lines').select().eq('collection', collection).order('position');
  return List<Map<String, dynamic>>.from(rows);
});

class CuratedScreen extends ConsumerStatefulWidget {
  final String collection;
  final String title;
  final String intro;
  const CuratedScreen({super.key, required this.collection, required this.title, required this.intro});

  @override
  ConsumerState<CuratedScreen> createState() => _CuratedScreenState();
}

class _CuratedScreenState extends ConsumerState<CuratedScreen> {
  String? _category;
  String _query = '';
  bool _favoritesOnly = false;

  bool get _isFlirt => widget.collection == 'flirt';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final data = ref.watch(curatedProvider(widget.collection));
    final favs = ref.watch(favoritesProvider).valueOrNull ?? <String>{};

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.black,
        title: Text(widget.title, style: t.titleLarge?.copyWith(color: AppColors.gold)),
      ),
      body: SafeArea(
        child: data.when(
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.gold)),
          error: (_, __) => const Center(child: Text('Could not load content.')),
          data: (rows) {
            final categories = <String>[];
            for (final r in rows) {
              final c = r['category'] as String;
              if (!categories.contains(c)) categories.add(c);
            }
            final shown = rows.where((r) {
              final hay = '${r['title'] ?? ''} ${r['text']}'.toLowerCase();
              return (_category == null || r['category'] == _category) &&
                  (_query.isEmpty || hay.contains(_query)) &&
                  (!_favoritesOnly || favs.contains(r['id']));
            }).toList();

            return Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.l, AppSpacing.s, AppSpacing.l, AppSpacing.s),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.intro, style: t.bodySmall),
                  const SizedBox(height: AppSpacing.m),
                  TextField(
                    decoration: const InputDecoration(hintText: 'Search', prefixIcon: Icon(Icons.search)),
                    onChanged: (v) => setState(() => _query = v.toLowerCase()),
                  ),
                ]),
              ),
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.s),
                      child: ChoiceChip(
                        label: const Text('All'),
                        selected: _category == null,
                        onSelected: (_) => setState(() => _category = null),
                      ),
                    ),
                    for (final c in categories)
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.s),
                        child: ChoiceChip(
                          label: Text(c),
                          selected: _category == c,
                          onSelected: (_) => setState(() => _category = c),
                        ),
                      ),
                    FilterChip(
                      label: const Text('Favorites'),
                      selected: _favoritesOnly,
                      onSelected: (v) => setState(() => _favoritesOnly = v),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: shown.isEmpty
                    ? const Center(child: Text('Nothing here yet.'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(AppSpacing.l),
                        itemCount: shown.length,
                        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.m),
                        itemBuilder: (_, i) => _EntryCard(
                          row: shown[i],
                          isFlirt: _isFlirt,
                          isFavorite: favs.contains(shown[i]['id']),
                        ),
                      ),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

class _EntryCard extends ConsumerWidget {
  final Map<String, dynamic> row;
  final bool isFlirt;
  final bool isFavorite;
  const _EntryCard({required this.row, required this.isFlirt, required this.isFavorite});

  static Widget _label(String text, {Color color = AppColors.gold}) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text.toUpperCase(),
            style: TextStyle(fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w700, color: color)),
      );

  static Widget _dots(int n, int max) => Row(children: [
        for (var i = 1; i <= max; i++)
          Container(
            width: 9,
            height: 9,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i <= n ? AppColors.gold : const Color(0xFF333333),
              boxShadow: i <= n ? const [BoxShadow(color: AppColors.glow, blurRadius: 6)] : null,
            ),
          ),
      ]);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final id = row['id'] as String;
    final text = row['text'] as String;
    final title = row['title'] as String?;
    final p = (row['success_estimate'] as num?)?.toInt() ?? 0;
    final difficulty = '${row['difficulty'] ?? 'Medium'}';
    final dn = {'Easy': 1, 'Medium': 2, 'Hard': 3}[difficulty] ?? 2;
    final conf = (row['confidence_required'] as num?)?.toInt() ?? 3;
    final responses = [for (final r in (row['responses'] as List? ?? const [])) '$r'];
    final alternatives = [for (final a in (row['alternatives'] as List? ?? const [])) '$a'];

    Widget section(String label, Widget child, {Color color = AppColors.gold}) =>
        Padding(padding: const EdgeInsets.only(top: AppSpacing.l), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_label(label, color: color), child]));

    return Card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.all(AppSpacing.l + 2),
          childrenPadding: const EdgeInsets.fromLTRB(AppSpacing.l + 2, 0, AppSpacing.l + 2, AppSpacing.l + 2),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          title: isFlirt
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.goldGradient),
                    child: Text('${row['position']}', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                  const SizedBox(width: AppSpacing.m),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      Text(text, style: t.bodySmall),
                    ]),
                  ),
                ])
              : Text('“$text”', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w500)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.m),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                flex: 3,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _label('Response rate'),
                  GoldProgress(value: p / 100),
                  const SizedBox(height: 4),
                  Text('~$p% est.', style: t.bodySmall),
                ]),
              ),
              const SizedBox(width: AppSpacing.l),
              Expanded(
                flex: 2,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_label('Difficulty'), _dots(dn, 3)]),
              ),
              const SizedBox(width: AppSpacing.m),
              Expanded(
                flex: 2,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_label('Confidence'), _dots(conf, 5)]),
              ),
            ]),
          ),
          trailing: IconButton(
            tooltip: isFavorite ? 'Remove from favorites' : 'Add to favorites',
            icon: Icon(isFavorite ? Icons.star : Icons.star_border, color: AppColors.gold),
            onPressed: () async {
              if (isFavorite) {
                await sb.from('favorites').delete().eq('user_id', uid).eq('line_id', id);
              } else {
                await sb.from('favorites').insert({'user_id': uid, 'line_id': id});
              }
              ref.invalidate(favoritesProvider);
            },
          ),
          children: [
            const Divider(color: AppColors.line),
            section('Best when', Text('${row['best_situation'] ?? ''}')),
            if (responses.isNotEmpty)
              section(
                'They might say',
                Wrap(spacing: AppSpacing.s, runSpacing: AppSpacing.s, children: [
                  for (final r in responses)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.charcoal,
                        border: Border.all(color: AppColors.line),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16), topRight: Radius.circular(16),
                          bottomRight: Radius.circular(16), bottomLeft: Radius.circular(4),
                        ),
                      ),
                      child: Text(r),
                    ),
                ]),
              ),
            section('Delivery', Text('${row['voice_delivery'] ?? ''}')),
            section(
              'Watch out',
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.m),
                decoration: const BoxDecoration(
                  color: Color(0x12E0A96D),
                  border: Border(left: BorderSide(color: Color(0xFFE0A96D), width: 3)),
                  borderRadius: BorderRadius.only(topRight: Radius.circular(12), bottomRight: Radius.circular(12)),
                ),
                child: Text('${row['red_flags'] ?? ''}'),
              ),
              color: const Color(0xFFE0A96D),
            ),
            if (alternatives.isNotEmpty)
              section('Try instead', Text('“${alternatives.first}”', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w500))),
            const SizedBox(height: AppSpacing.m),
            Text('Response rate is a starting estimate, not a measured result.', style: t.bodySmall),
          ],
        ),
      ),
    );
  }
}
