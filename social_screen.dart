import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/data_providers.dart';
import '../../widgets/common.dart';

const _tabs = <String, String>{
  'Openers': 'opener',
  'Flirting': 'flirting',
  'Conversation Flow': 'flow',
  'Attraction Building': 'attraction',
};

final linesProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, category) async {
  final rows = await sb
      .from('lines')
      .select()
      .eq('category', category)
      .order('popularity', ascending: false);
  return List<Map<String, dynamic>>.from(rows);
});

final favoritesProvider = FutureProvider.autoDispose<Set<String>>((ref) async {
  final rows = await sb.from('favorites').select('line_id').eq('user_id', uid);
  return {for (final r in rows) r['line_id'] as String};
});

class SocialScreen extends StatefulWidget {
  const SocialScreen({super.key});

  @override
  State<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends State<SocialScreen> {
  String _query = '';
  bool _favoritesOnly = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return DefaultTabController(
      length: _tabs.length,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.l, AppSpacing.l, AppSpacing.l, AppSpacing.s),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Social', style: t.headlineLarge),
            const SizedBox(height: AppSpacing.m),
            AppCard(
              hero: true,
              onTap: () => context.push('/library'),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Line Library', style: t.titleLarge?.copyWith(color: AppColors.goldPremium)),
                    Text('325 lines in 13 categories, with examples', style: t.bodySmall),
                  ]),
                ),
                const Icon(Icons.chevron_right, color: AppColors.gold),
              ]),
            ),
            const SizedBox(height: AppSpacing.m),
            Row(children: [
              Expanded(
                child: AppCard(
                  onTap: () => context.push('/openers'),
                  child: Text('Best Openers\n50 openers', style: t.titleLarge?.copyWith(color: AppColors.goldPremium)),
                ),
              ),
              const SizedBox(width: AppSpacing.m),
              Expanded(
                child: AppCard(
                  onTap: () => context.push('/flirts'),
                  child: Text('Flirt Database\n50 techniques', style: t.titleLarge?.copyWith(color: AppColors.goldPremium)),
                ),
              ),
            ]),
            const SizedBox(height: AppSpacing.m),
            TextField(
              decoration: const InputDecoration(hintText: 'Search lines and tips', prefixIcon: Icon(Icons.search)),
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
            ),
            const SizedBox(height: AppSpacing.s),
            FilterChip(
              label: const Text('Favorites'),
              selected: _favoritesOnly,
              onSelected: (v) => setState(() => _favoritesOnly = v),
            ),
          ]),
        ),
        TabBar(isScrollable: true, tabs: [for (final k in _tabs.keys) Tab(text: k)]),
        Expanded(
          child: TabBarView(children: [
            for (final category in _tabs.values)
              _LineList(category: category, query: _query, favoritesOnly: _favoritesOnly),
          ]),
        ),
      ]),
    );
  }
}

class _LineList extends ConsumerWidget {
  final String category;
  final String query;
  final bool favoritesOnly;
  const _LineList({required this.category, required this.query, required this.favoritesOnly});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lines = ref.watch(linesProvider(category));
    final favs = ref.watch(favoritesProvider).valueOrNull ?? <String>{};

    return lines.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.gold)),
      error: (_, __) => const Center(child: Text('Could not load content.')),
      data: (rows) {
        final filtered = rows.where((r) {
          final text = (r['text'] as String).toLowerCase();
          final matches = query.isEmpty || text.contains(query);
          final fav = !favoritesOnly || favs.contains(r['id']);
          return matches && fav;
        }).toList();
        if (filtered.isEmpty) {
          return const Center(child: Text('Nothing here yet.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.l),
          itemCount: filtered.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.m),
          itemBuilder: (context, i) {
            final r = filtered[i];
            final id = r['id'] as String;
            final isFav = favs.contains(id);
            return AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Text('“${r['text']}”',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w500)),
                  ),
                  IconButton(
                    tooltip: isFav ? 'Remove from favorites' : 'Add to favorites',
                    icon: Icon(isFav ? Icons.star : Icons.star_border, color: AppColors.gold),
                    onPressed: () async {
                      if (isFav) {
                        await sb.from('favorites').delete().eq('user_id', uid).eq('line_id', id);
                      } else {
                        await sb.from('favorites').insert({'user_id': uid, 'line_id': id});
                      }
                      ref.invalidate(favoritesProvider);
                    },
                  ),
                ]),
                if (((r['popularity'] as int?) ?? 0) >= 50) const TagChip('Popular'),
              ]),
            );
          },
        );
      },
    );
  }
}
