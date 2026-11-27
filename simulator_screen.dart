import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../app/theme.dart';
import '../../widgets/common.dart';
import 'charts.dart';
import 'studio_repository.dart';

const _personas = <(String, String, String)>[
  ('shy', 'Shy woman', 'Reserved, careful, emotional'),
  ('confident', 'Confident woman', 'Direct, independent, demanding'),
  ('party', 'Party girl', 'Playful, humorous, spontaneous'),
  ('career', 'Career woman', 'Intelligent, ambitious, selective'),
  ('romantic', 'Romantic woman', 'Deep, emotional, connection-oriented'),
  ('challenging', 'Challenging woman', 'Tests you, asks many questions'),
];

class SimulatorScreen extends StatefulWidget {
  const SimulatorScreen({super.key});

  @override
  State<SimulatorScreen> createState() => _SimulatorScreenState();
}

class _SimulatorScreenState extends State<SimulatorScreen> {
  final _repo = StudioRepository();
  final _input = TextEditingController();
  final _messages = <(bool, String)>[]; // (fromUser, text)
  String? _sessionId;
  String? _persona;
  String _mode = 'chat';
  bool _busy = false;
  bool _premiumNeeded = false;
  String? _error;
  Map<String, dynamic>? _feedback;
  Map<String, dynamic>? _report;

  // Voice call mode: she speaks (text to speech) and you answer by voice (speech to text).
  final _tts = FlutterTts();
  final _stt = SpeechToText();
  bool _sttReady = false;
  bool _listening = false;
  bool _speaking = false;

  @override
  void initState() {
    super.initState();
    _tts.setCompletionHandler(() {
      if (!mounted) return;
      setState(() => _speaking = false);
      if (_mode == 'call' && _sessionId != null && _report == null && !_busy) _listen();
    });
  }

  @override
  void dispose() {
    _tts.stop();
    _stt.cancel();
    _input.dispose();
    super.dispose();
  }

  Future<void> _afterReply(String reply) async {
    if (_mode != 'call' || !mounted) return;
    await _stt.cancel();
    setState(() {
      _listening = false;
      _speaking = true;
    });
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.speak(reply);
  }

  Future<void> _listen() async {
    if (_listening) {
      await _stt.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    if (!_sttReady) {
      _sttReady = await _stt.initialize(onError: (_) {
        if (mounted) setState(() => _listening = false);
      });
    }
    if (!_sttReady) {
      setState(() => _error = 'Speech recognition is not available. You can type instead.');
      return;
    }
    setState(() {
      _listening = true;
      _error = null;
    });
    await _stt.listen(
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 4),
      onResult: (r) {
        if (!mounted) return;
        setState(() => _input.text = r.recognizedWords);
        if (r.finalResult) {
          setState(() => _listening = false);
          _send();
        }
      },
    );
  }

  Future<void> _guard(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on PremiumRequiredException {
      setState(() => _premiumNeeded = true);
    } on StudioException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'The simulator is unavailable right now.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start(String persona) => _guard(() async {
        final r = await _repo.simStart(persona, _mode);
        setState(() {
          _persona = persona;
          _sessionId = r['session_id'] as String;
          _messages
            ..clear()
            ..add((false, '${r['reply']}'));
          _feedback = null;
          _report = null;
        });
        _afterReply('${r['reply']}');
      });

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy || _sessionId == null) return;
    _input.clear();
    setState(() => _messages.add((true, text)));
    await _guard(() async {
      final r = await _repo.simTurn(_sessionId!, text);
      setState(() {
        _messages.add((false, '${r['reply']}'));
        _feedback = r;
      });
      _afterReply('${r['reply']}');
    });
  }

  Future<void> _end() => _guard(() async {
        await _tts.stop();
        await _stt.cancel();
        final r = await _repo.simEnd(_sessionId!);
        setState(() => _report = r);
      });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.black,
        title: Text('Conversation Simulator', style: t.titleLarge?.copyWith(color: AppColors.gold)),
      ),
      body: SafeArea(
        child: _premiumNeeded
            ? Padding(
                padding: const EdgeInsets.all(AppSpacing.l),
                child: AppCard(
                  hero: true,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const TagChip('Premium'),
                    const SizedBox(height: AppSpacing.m),
                    Text('Practice with realistic characters and get live feedback.', style: t.titleLarge),
                    const SizedBox(height: AppSpacing.l),
                    GoldButton(label: 'Unlock Premium', onPressed: () => context.push('/paywall')),
                  ]),
                ),
              )
            : _report != null
                ? _reportView(t)
                : _sessionId == null
                    ? _picker(t)
                    : _chat(t),
      ),
    );
  }

  Widget _picker(TextTheme t) => ListView(padding: const EdgeInsets.all(AppSpacing.l), children: [
        Text('Practice with fictional characters. Warmth is earned through interest, humor and respect.', style: t.bodySmall),
        const SizedBox(height: AppSpacing.m),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'chat', label: Text('Chat')),
            ButtonSegment(value: 'call', label: Text('Voice call')),
          ],
          selected: {_mode},
          onSelectionChanged: (v) => setState(() => _mode = v.first),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: AppSpacing.m), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
        const SizedBox(height: AppSpacing.l),
        for (final p in _personas) ...[
          AppCard(
            onTap: _busy ? null : () => _start(p.$1),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.$2, style: t.titleLarge?.copyWith(color: AppColors.goldPremium)),
              Text(p.$3, style: t.bodySmall),
            ]),
          ),
          const SizedBox(height: AppSpacing.m),
        ],
        if (_busy) const Center(child: CircularProgressIndicator(color: AppColors.gold)),
      ]);

  Widget _chat(TextTheme t) {
    final f = _feedback;
    final scores = f == null ? null : Map<String, dynamic>.from(f['scores'] as Map);
    const labels = {'attraction': 'Attraction', 'emotional': 'Emotional impact', 'confidence': 'Confidence', 'humor': 'Humor', 'flirt': 'Flirt quality', 'lead': 'Conversation lead'};
    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.all(AppSpacing.l), children: [
          if (_mode == 'call')
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.m),
              child: Text(
                _listening ? 'Listening…' : (_speaking ? 'She is speaking…' : (_busy ? 'Thinking…' : 'Your turn: tap the microphone')),
                textAlign: TextAlign.center,
                style: t.bodySmall?.copyWith(color: AppColors.gold),
              ),
            ),
          for (final m in _messages)
            Align(
              alignment: m.$1 ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.s),
                padding: const EdgeInsets.all(AppSpacing.m + 2),
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                decoration: BoxDecoration(
                  gradient: m.$1 ? AppColors.goldGradient : null,
                  color: m.$1 ? null : AppColors.card,
                  border: m.$1 ? null : Border.all(color: AppColors.line),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(m.$2, style: TextStyle(color: m.$1 ? Colors.black : AppColors.text)),
              ),
            ),
          if (_busy) const Center(child: CircularProgressIndicator(color: AppColors.gold)),
          if (_error != null) Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          if (f != null && scores != null) ...[
            const SizedBox(height: AppSpacing.m),
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Live feedback', style: t.titleLarge),
                const SizedBox(height: AppSpacing.s),
                for (final e in labels.entries) ...[
                  Text('${e.value}  ${(scores[e.key] as num?)?.toInt() ?? 0}', style: t.bodySmall),
                  GoldProgress(value: ((scores[e.key] as num?)?.toInt() ?? 0) / 100),
                  const SizedBox(height: 6),
                ],
                if (f['respect_flag'] == true)
                  const Padding(padding: EdgeInsets.only(top: 6), child: Text('Respect check: this could feel pushy or disrespectful.', style: TextStyle(color: Color(0xFFE0A96D)))),
                const SizedBox(height: 6),
                Text('Good: ${f['good']}', style: const TextStyle(color: AppColors.success)),
                Text('Better: ${f['improve']}', style: const TextStyle(color: Color(0xFFE0A96D))),
                const SizedBox(height: 6),
                Text('Try instead', style: t.bodySmall),
                for (final s in (f['suggestions'] as List? ?? const [])) Text('•  $s'),
              ]),
            ),
          ],
        ]),
      ),
      Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Row(children: [
          Expanded(child: TextField(controller: _input, maxLength: 800, onSubmitted: (_) => _send(), decoration: const InputDecoration(hintText: 'Write your message', counterText: ''))),
          const SizedBox(width: AppSpacing.s),
          if (_mode == 'call')
            IconButton(
              tooltip: _listening ? 'Stop listening' : 'Speak',
              icon: Icon(_listening ? Icons.mic : Icons.mic_none, color: AppColors.gold),
              onPressed: _busy ? null : _listen,
            ),
          GoldButton(label: 'Send', expanded: false, onPressed: _busy ? null : _send),
          TextButton(onPressed: _busy ? null : _end, child: const Text('End')),
        ]),
      ),
    ]);
  }

  Widget _reportView(TextTheme t) {
    final r = _report!;
    int v(String k) => (r[k] as num?)?.toInt() ?? 0;
    return ListView(padding: const EdgeInsets.all(AppSpacing.l), children: [
      AppCard(
        hero: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Your report', style: t.headlineMedium),
          const SizedBox(height: AppSpacing.l),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            ScoreRing(value: v('attraction'), label: 'Attraction'),
            ScoreRing(value: v('charisma'), label: 'Charisma'),
            ScoreRing(value: v('lead'), label: 'Conversation lead'),
          ]),
          const SizedBox(height: AppSpacing.l),
          Text('${r['report']}'),
          const SizedBox(height: AppSpacing.m),
          Text('Next steps', style: t.titleLarge?.copyWith(color: AppColors.gold)),
          for (final s in (r['next_steps'] as List? ?? const [])) Text('•  $s'),
        ]),
      ),
      const SizedBox(height: AppSpacing.m),
      GoldButton(
        label: 'Practice again',
        onPressed: () => setState(() {
          _report = null;
          _sessionId = null;
          _messages.clear();
          _feedback = null;
        }),
      ),
    ]);
  }
}
