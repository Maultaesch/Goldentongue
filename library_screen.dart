import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/data_providers.dart';
import '../../widgets/common.dart';
import '../social/social_screen.dart' show favoritesProvider;

const libraryCategories = <String>[
  'Funny',
  'Playful',
  'Confident',
  'Romantic',
  'Intelligent',
  'Situational',
  'Text message',
  'Instagram',
  'Dating apps',
  'Travel',
  'Luxury',
  'Business class traveler',
  'Social circle',
];

final libraryLinesProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, category) async {
  final rows = await sb
      .from('lines')
      .select()
      .eq('collection', 'library')
      .eq('category', category)
      .order('popularity', ascending: false)
      .order('text');
  return List<Map<String, dynamic>>.from(rows);
});

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  String _category = libraryCategories.first;
  String _query = '';
  bool _favoritesOnly = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final lines = ref.watch(libraryLinesProvider(_category));
    final favs = ref.watch(favoritesProvider).valueOrNull ?? <String>{};

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.black,
        title: Text('Line Library', style: t.titleLarge?.copyWith(color: AppColors.gold)),
      ),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.l, AppSpacing.s, AppSpacing.l, AppSpacing.s),
            child: TextField(
              decoration: const InputDecoration(hintText: 'Search this category', prefixIcon: Icon(Icons.search)),
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
              children: [
                for (final c in libraryCategories)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.s),
                    child: ChoiceChip(
                      label: Text(c),
                      selected: c == _category,
                      selectedColor: AppColors.card,
                      side: BorderSide(color: c == _category ? AppColors.gold : AppColors.line),
                      labelStyle: TextStyle(color: c == _category ? AppColors.goldPremium : AppColors.text),
                      onSelected: (_) => setState(() => _category = c),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
            child: Row(children: [
              Expanded(
                child: Text(
                  lines.maybeWhen(data: (r) => '${r.length} lines', orElse: () => ''),
                  style: t.bodySmall,
                ),
              ),
              FilterChip(
                label: const Text('Favorites'),
                selected: _favoritesOnly,
                onSelected: (v) => setState(() => _favoritesOnly = v),
              ),
            ]),
          ),
          Expanded(
            child: lines.when(
              loading: () => const Center(child: CircularProgressIndicator(color: AppColors.gold)),
              error: (_, __) => const Center(child: Text('Could not load the library.')),
              data: (rows) {
                final shown = rows.where((r) {
                  final text = (r['text'] as String).toLowerCase();
                  return (_query.isEmpty || text.contains(_query)) &&
                      (!_favoritesOnly || favs.contains(r['id']));
                }).toList();
                if (shown.isEmpty) return const Center(child: Text('Nothing here yet.'));
                return ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.l),
                  itemCount: shown.length,
                  separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.m),
                  itemBuilder: (context, i) {
                    final r = shown[i];
                    final id = r['id'] as String;
                    final isFav = favs.contains(id);
                    return AppCard(
                      onTap: () => context.push('/library/line', extra: r),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          child: Text('“${r['text']}”',
                              style: t.titleLarge?.copyWith(fontWeight: FontWeight.w500)),
                        ),
                        Icon(isFav ? Icons.star : Icons.chevron_right,
                            color: isFav ? AppColors.gold : AppColors.textSecondary),
                      ]),
                    );
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
