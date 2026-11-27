import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../widgets/common.dart';
import 'studio_repository.dart';

class BlueprintScreen extends StatefulWidget {
  const BlueprintScreen({super.key});

  @override
  State<BlueprintScreen> createState() => _BlueprintScreenState();
}

class _BlueprintScreenState extends State<BlueprintScreen> {
  final _repo = StudioRepository();
  Map<String, dynamic>? _data;
  final _done = <int>{};
  bool _busy = false;
  bool _premiumNeeded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repo.latestBlueprint().then((d) {
      if (mounted && d != null) setState(() => _data = d);
    }).catchError((_) {});
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final d = await _repo.createBlueprint();
      setState(() {
        _data = d;
        _done.clear();
      });
    } on PremiumRequiredException {
      setState(() => _premiumNeeded = true);
    } on StudioException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'The blueprint could not be created. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final d = _data;
    List<String> list(String k) => [for (final x in (d?[k] as List? ?? const [])) '$x'];
    final daily = [for (final x in (d?['daily'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
    Widget bullets(String title, List<String> items, Color color) => Padding(
          padding: const EdgeInsets.only(top: AppSpacing.m),
          child: AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: t.titleLarge?.copyWith(color: color)),
              const SizedBox(height: AppSpacing.s),
              for (final i in items) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('•  $i')),
            ]),
          ),
        );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.black,
        title: Text('My Charm Blueprint', style: t.titleLarge?.copyWith(color: AppColors.gold)),
      ),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(AppSpacing.l), children: [
          AppCard(
            hero: true,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Built from your voice analyses and simulator sessions.', style: t.bodySmall),
              const SizedBox(height: AppSpacing.l),
              if (_busy)
                const Center(child: CircularProgressIndicator(color: AppColors.gold))
              else
                GoldButton(label: d == null ? 'Create my blueprint' : 'Refresh my blueprint', onPressed: _create),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: AppSpacing.m), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
              if (_premiumNeeded) ...[
                const SizedBox(height: AppSpacing.m),
                const Text('The Blueprint is part of Premium.'),
                const SizedBox(height: AppSpacing.s),
                GoldButton(label: 'Unlock Premium', onPressed: () => context.push('/paywall')),
              ],
            ]),
          ),
          if (d != null) ...[
            bullets('Your strengths', list('strengths'), AppColors.success),
            bullets('Your growth areas', list('weaknesses'), const Color(0xFFE0A96D)),
            const SizedBox(height: AppSpacing.m),
            AppCard(
              hero: true,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text("Today's training", style: t.titleLarge),
                Text('${d['focus'] ?? ''}', style: t.bodySmall),
                const SizedBox(height: AppSpacing.s),
                for (var i = 0; i < daily.length; i++)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _done.contains(i),
                    onChanged: (v) => setState(() => v == true ? _done.add(i) : _done.remove(i)),
                    title: Text('${daily[i]['task']}'),
                    subtitle: Text('${daily[i]['minutes']} min', style: t.bodySmall),
                  ),
                GoldProgress(value: daily.isEmpty ? 0 : _done.length / daily.length),
                const SizedBox(height: AppSpacing.s),
                Text('Weekly goal: ${d['weekly_goal'] ?? ''}', style: t.bodySmall),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}
