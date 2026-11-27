import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/data_providers.dart';
import '../../widgets/common.dart';
import '../social/social_screen.dart' show favoritesProvider;

class LineDetailScreen extends ConsumerWidget {
  final Map<String, dynamic> line;
  const LineDetailScreen({super.key, required this.line});

  void _copy(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Copied')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final id = line['id'] as String;
    final text = line['text'] as String;
    final favs = ref.watch(favoritesProvider).valueOrNull ?? <String>{};
    final isFav = favs.contains(id);

    final scores = Map<String, dynamic>.from((line['scores'] as Map?) ?? const {});
    final example = [for (final e in (line['example'] as List? ?? const [])) Map<String, dynamic>.from(e as Map)];
    final alternatives = [for (final a in (line['alternatives'] as List? ?? const [])) '$a'];
    final why = line['why'] as String? ?? '';
    final recovery = line['recovery'] as String? ?? '';
    final estimated = scores['estimated'] == true;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.black,
        title: Text(line['category'] as String? ?? 'Line', style: t.titleLarge?.copyWith(color: AppColors.gold)),
        actions: [
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
        ],
      ),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(AppSpacing.l), children: [
          AppCard(
            hero: true,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SelectableText('“$text”', style: t.headlineMedium),
              const SizedBox(height: AppSpacing.l),
              GoldButton(label: 'Copy line', onPressed: () => _copy(context, text)),
            ]),
          ),
          const SizedBox(height: AppSpacing.m),
          Row(children: [
            Expanded(child: _Meter(label: 'Effectiveness', value: (scores['effectiveness'] as num?)?.toInt() ?? 0, max: 100)),
            const SizedBox(width: AppSpacing.s),
            Expanded(child: _Meter(label: 'Confidence', value: (scores['confidence'] as num?)?.toInt() ?? 0, max: 100)),
            const SizedBox(width: AppSpacing.s),
            Expanded(child: _Meter(label: 'Difficulty', value: (scores['difficulty'] as num?)?.toInt() ?? 0, max: 5)),
          ]),
          if (estimated)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s),
              child: Text('Scores are estimates and improve as real feedback comes in.', style: t.bodySmall),
            ),
          if (why.isNotEmpty) _Section(title: 'Why it works', child: Text(why)),
          if (example.isNotEmpty)
            _Section(
              title: 'Example conversation',
              child: Column(children: [for (final m in example) _Bubble(m['role'] == 'you', '${m['text']}')]),
            ),
          if (alternatives.isNotEmpty)
            _Section(
              title: 'Alternative versions',
              child: Column(children: [
                for (final a in alternatives)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('“$a”'),
                    trailing: IconButton(icon: const Icon(Icons.copy, size: 18), onPressed: () => _copy(context, a)),
                  ),
              ]),
            ),
          if (recovery.isNotEmpty) _Section(title: 'If it falls flat', child: Text(recovery)),
        ]),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.l),
      child: AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.gold)),
          const SizedBox(height: AppSpacing.s),
          child,
        ]),
      ),
    );
  }
}

class _Meter extends StatelessWidget {
  final String label;
  final int value;
  final int max;
  const _Meter({required this.label, required this.value, required this.max});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: t.bodySmall),
        const SizedBox(height: 4),
        Text(max == 100 ? '$value' : '$value/$max', style: t.titleLarge?.copyWith(color: AppColors.gold)),
        const SizedBox(height: AppSpacing.s),
        GoldProgress(value: max == 0 ? 0 : value / max),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  final bool me;
  final String text;
  const _Bubble(this.me, this.text);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: me ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.s),
        padding: const EdgeInsets.all(AppSpacing.m),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          gradient: me ? AppColors.goldGradient : null,
          color: me ? null : AppColors.charcoal,
          border: me ? null : Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(text, style: TextStyle(color: me ? Colors.black : AppColors.text)),
      ),
    );
  }
}
