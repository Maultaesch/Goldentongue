import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:record/record.dart';

import '../../app/theme.dart';
import '../../widgets/common.dart';
import 'acoustics.dart';
import 'charts.dart';
import 'studio_repository.dart';

const _dims = <(String, String)>[
  ('attraction', 'Attraction'),
  ('confidence', 'Confidence'),
  ('dominance', 'Assertiveness'),
  ('relaxation', 'Relaxation'),
  ('emotion', 'Emotion'),
  ('pace', 'Pace'),
  ('pitch', 'Pitch'),
  ('articulation', 'Articulation'),
  ('flirt', 'Flirt factor'),
  ('charisma', 'Charisma'),
];

class VoiceScreen extends StatefulWidget {
  const VoiceScreen({super.key});

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen> {
  final _repo = StudioRepository();
  final _recorder = AudioRecorder();
  Timer? _ticker;
  DateTime? _t0;
  StreamSubscription<Uint8List>? _sub;
  final _pcm = BytesBuilder(copy: false);
  final _acoustics = AcousticAnalyzer();
  double _level = 0;
  int _seconds = 0;
  bool _recording = false;
  bool _busy = false;
  bool _needsUpgrade = false;
  String? _error;
  Map<String, dynamic>? _result;

  @override
  void dispose() {
    _ticker?.cancel();
    _sub?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _result = null;
      _needsUpgrade = false;
    });
    if (!await _recorder.hasPermission()) {
      setState(() => _error = 'Microphone permission is needed to record.');
      return;
    }
    _pcm.clear();
    _acoustics.reset();
    final stream = await _recorder.startStream(
      const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1),
    );
    _sub = stream.listen((chunk) {
      _pcm.add(chunk);
      _acoustics.feed(chunk);
    });
    _t0 = DateTime.now();
    setState(() {
      _recording = true;
      _seconds = 0;
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final s = DateTime.now().difference(_t0!).inSeconds;
      if (s >= 60) {
        _stop();
      } else if (mounted) {
        setState(() {
          _seconds = s;
          _level = (_acoustics.lastRms * 6).clamp(0.0, 1.0);
        });
      }
    });
  }

  Future<void> _stop() async {
    _ticker?.cancel();
    final seconds = DateTime.now().difference(_t0!).inSeconds.clamp(0, 60);
    await _recorder.stop();
    await _sub?.cancel();
    if (!mounted) return;
    setState(() => _recording = false);
    if (seconds < 5) {
      setState(() => _error = 'Too short. Please speak for at least 5 seconds.');
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await _repo.analyzeVoice(wavFromPcm16(_pcm.toBytes()), seconds, metrics: _acoustics.finish());
      if (mounted) setState(() => _result = result);
    } on LimitReachedException {
      setState(() {
        _error = 'Free plan: 1 analysis per week. Premium is unlimited.';
        _needsUpgrade = true;
      });
    } on StudioException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'The analysis could not be completed. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.black,
        title: Text('Voice Analyzer', style: t.titleLarge?.copyWith(color: AppColors.gold)),
      ),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(AppSpacing.l), children: [
          AppCard(
            hero: true,
            child: Column(children: [
              Text(
                'Record up to 60 seconds. The AI estimates how your delivery may come across. Scores are estimates of delivery, not a verdict on you.',
                style: t.bodySmall,
              ),
              const SizedBox(height: AppSpacing.l),
              Text('${_seconds ~/ 60}:${(_seconds % 60).toString().padLeft(2, '0')}', style: t.displayMedium),
              GoldProgress(value: _seconds / 60),
              if (_recording) ...[const SizedBox(height: AppSpacing.s), GoldProgress(value: _level)],
              const SizedBox(height: AppSpacing.l),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.m),
                  child: CircularProgressIndicator(color: AppColors.gold),
                )
              else
                GoldButton(label: _recording ? 'Stop and analyze' : 'Start recording', onPressed: _recording ? _stop : _start),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.m),
                Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ],
              if (_needsUpgrade) ...[
                const SizedBox(height: AppSpacing.m),
                GoldButton(label: 'Upgrade to Premium', onPressed: () => context.push('/paywall')),
              ],
            ]),
          ),
          if (_result != null) ..._resultWidgets(_result!, t),
        ]),
      ),
    );
  }

  List<Widget> _resultWidgets(Map<String, dynamic> r, TextTheme t) {
    final scores = Map<String, dynamic>.from(r['scores'] as Map);
    int s(String k) => (scores[k] as num?)?.toInt() ?? 0;
    List<String> list(String k) => [for (final x in (r[k] as List? ?? const [])) '$x'];
    Widget bullets(String title, List<String> items, {Color color = AppColors.gold}) => Padding(
          padding: const EdgeInsets.only(top: AppSpacing.m),
          child: AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: t.titleLarge?.copyWith(color: color)),
              const SizedBox(height: AppSpacing.s),
              for (final i in items) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('•  $i')),
            ]),
          ),
        );
    return [
      const SizedBox(height: AppSpacing.m),
      AppCard(
        hero: true,
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          ScoreRing(value: s('attraction'), label: 'Attraction'),
          ScoreRing(value: s('charisma'), label: 'Charisma'),
          ScoreRing(value: s('confidence'), label: 'Confidence'),
        ]),
      ),
      const SizedBox(height: AppSpacing.m),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Voice profile', style: t.titleLarge),
          RadarChart(labels: [for (final d in _dims) d.$2], values: [for (final d in _dims) s(d.$1)]),
        ]),
      ),
      const SizedBox(height: AppSpacing.m),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('How you may come across', style: t.titleLarge),
          const SizedBox(height: AppSpacing.s),
          Text('${r['impression'] ?? ''}'),
          const SizedBox(height: AppSpacing.s),
          Text('${r['note'] ?? ''} Scores are AI estimates of delivery.', style: t.bodySmall),
        ]),
      ),
      _metricsCard(r['metrics'], t),
      bullets('Strengths', list('strengths'), color: AppColors.success),
      bullets('To improve', list('weaknesses'), color: const Color(0xFFE0A96D)),
      bullets('Instant tips', list('tips')),
    ];
  }

  Widget _metricsCard(dynamic raw, TextTheme t) {
    final m = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    num? n(String k) => m[k] is num ? m[k] as num : null;
    final rows = <(String, num?, double, double, String)>[
      ('Pace', n('wpm'), 130, 160, 'wpm'),
      ('Pitch variety', n('pitchRangeSemitones'), 4, 9, 'semitones'),
      ('Pauses', n('pauseRatio') == null ? null : (n('pauseRatio')! * 100).round(), 12, 30, '%'),
      ('Filler words', n('fillers'), 0, 2, 'count'),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.m),
      child: AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Measured on your device', style: t.titleLarge),
          const SizedBox(height: 4),
          Text('Illustrative target ranges for clear, confident delivery. Not a survey of real people.', style: t.bodySmall),
          const SizedBox(height: AppSpacing.m),
          for (final (label, value, lo, hi, unit) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: value == null
                  ? Text('$label: not measured', style: t.bodySmall)
                  : Row(children: [
                      Expanded(child: Text('$label  $value $unit')),
                      Text(
                        value < lo ? 'below' : (value > hi ? 'above' : 'in range'),
                        style: TextStyle(
                          color: value < lo || value > hi ? const Color(0xFFE0A96D) : AppColors.success,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('(${lo.toInt()} to ${hi.toInt()})', style: t.bodySmall),
                    ]),
            ),
          if (n('pitchMedianHz') != null) Text('Median pitch ${n('pitchMedianHz')} Hz', style: t.bodySmall),
        ]),
      ),
    );
  }
}
