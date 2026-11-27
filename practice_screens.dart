import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/data_providers.dart';
import '../../widgets/common.dart';
import '../studio/charts.dart';
import '../studio/studio_repository.dart';
import 'exercise_result.dart';

/// Key format: "track|category", for example "deep_talk|Dreams".
final exercisesProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, key) async {
  final parts = key.split('|');
  final rows = await sb.from('exercises').select().eq('track', parts[0]).eq('category', parts[1]).order('position');
  return List<Map<String, dynamic>>.from(rows);
});

class PracticeListScreen extends ConsumerWidget {
  final String track;
  final String category;
  const PracticeListScreen({super.key, required this.track, required this.category});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final data = ref.watch(exercisesProvider('$track|$category'));
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.black,
        title: Text('Practice: $category', style: t.titleLarge?.copyWith(color: AppColors.gold)),
      ),
      body: SafeArea(
        child: data.when(
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.gold)),
          error: (_, __) => const Center(child: Text('Could not load the exercises.')),
          data: (rows) => rows.isEmpty
              ? const Center(child: Text('No exercises yet.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.l),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.m),
                  itemBuilder: (_, i) => AppCard(
                    onTap: () => context.push('/practice/exercise', extra: rows[i]),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${rows[i]['title']}', style: t.titleLarge?.copyWith(color: AppColors.goldPremium)),
                      const SizedBox(height: 4),
                      Text('${rows[i]['prompt']}', style: t.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                ),
        ),
      ),
    );
  }
}

class ExerciseScreen extends StatefulWidget {
  final Map<String, dynamic> exercise;
  const ExerciseScreen({super.key, required this.exercise});

  @override
  State<ExerciseScreen> createState() => _ExerciseScreenState();
}

class _ExerciseScreenState extends State<ExerciseScreen> {
  final _repo = StudioRepository();
  final _answer = TextEditingController();
  bool _busy = false;
  bool _needsUpgrade = false;
  String? _error;
  Map<String, dynamic>? _result;

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _answer.text.trim();
    if (text.length < 20) {
      setState(() => _error = 'Write at least a couple of sentences (20 characters or more).');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _needsUpgrade = false;
    });
    try {
      final r = await _repo.evaluateExercise(widget.exercise['id'] as String, text);
      setState(() => _result = r);
    } on PremiumRequiredException {
      setState(() => _needsUpgrade = true);
    } on LimitReachedException {
      setState(() => _error = 'You have reached today\'s practice limit. Come back tomorrow.');
    } on StudioException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'The evaluation could not be completed. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final ex = widget.exercise;
    final criteria = [for (final c in (ex['criteria'] as List? ?? const [])) '$c'];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.black,
        title: Text('${ex['title']}', style: t.titleLarge?.copyWith(color: AppColors.gold)),
      ),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(AppSpacing.l), children: [
          AppCard(
            hero: true,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Situation', style: t.bodySmall),
              const SizedBox(height: 4),
              Text('${ex['prompt']}', style: t.titleLarge),
              const SizedBox(height: AppSpacing.m),
              Text('A strong answer…', style: t.bodySmall),
              for (final c in criteria) Text('•  $c'),
            ]),
          ),
          const SizedBox(height: AppSpacing.m),
          if (_result == null) ...[
            TextField(
              controller: _answer,
              minLines: 5,
              maxLines: 10,
              maxLength: 1500,
              decoration: const InputDecoration(hintText: 'Write what you would say'),
            ),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            if (_needsUpgrade) ...[
              const Text('Practice with evaluation is part of Premium.'),
              const SizedBox(height: AppSpacing.s),
              GoldButton(label: 'Unlock Premium', onPressed: () => context.push('/paywall')),
            ],
            const SizedBox(height: AppSpacing.m),
            _busy
                ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
                : GoldButton(label: 'Get my evaluation', onPressed: _submit),
          ] else
            ..._resultWidgets(_result!, t),
        ]),
      ),
    );
  }

  List<Widget> _resultWidgets(Map<String, dynamic> raw, TextTheme t) {
    final r = ExerciseResult.fromJson(raw);
    return [
      AppCard(
        hero: true,
        child: Column(children: [
          ScoreRing(value: r.score, label: r.label),
          const SizedBox(height: AppSpacing.l),
          for (final c in r.criteria) ...[
            Align(alignment: Alignment.centerLeft, child: Text('${c.name}  ${c.score}')),
            GoldProgress(value: c.score / 100),
            Align(alignment: Alignment.centerLeft, child: Text(c.comment, style: t.bodySmall)),
            const SizedBox(height: AppSpacing.m),
          ],
        ]),
      ),
      const SizedBox(height: AppSpacing.m),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('What worked', style: t.titleLarge?.copyWith(color: AppColors.success)),
          Text(r.good),
          const SizedBox(height: AppSpacing.m),
          Text('Improve next', style: t.titleLarge?.copyWith(color: const Color(0xFFE0A96D))),
          Text(r.improve),
          const SizedBox(height: AppSpacing.m),
          Text('A stronger version', style: t.titleLarge?.copyWith(color: AppColors.gold)),
          Text(r.example),
        ]),
      ),
      const SizedBox(height: AppSpacing.m),
      GoldButton(label: 'Try again', onPressed: () => setState(() => _result = null)),
    ];
  }
}
