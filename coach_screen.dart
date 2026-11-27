import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../widgets/common.dart';
import 'coach_repository.dart';

const _prompts = [
  'What should I say next?',
  'Improve my message',
  'Create attraction',
  'Deepen conversation',
  'Business networking help',
  'Presentation coaching',
];

const _styleLabels = {
  'safe': 'Safe',
  'playful': 'Playful',
  'flirty': 'Flirty',
  'deep': 'Deep',
  'professional': 'Professional',
  'high_confidence': 'High confidence',
};

sealed class _Msg {}

class _UserMsg extends _Msg {
  final String text;
  _UserMsg(this.text);
}

class _CoachMsg extends _Msg {
  final CoachResult result;
  _CoachMsg(this.result);
}

class _NoticeMsg extends _Msg {
  final String text;
  final bool upgrade;
  _NoticeMsg(this.text, {this.upgrade = false});
}

class CoachScreen extends StatefulWidget {
  const CoachScreen({super.key});

  @override
  State<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends State<CoachScreen> {
  final _repo = CoachRepository();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_Msg>[];
  bool _busy = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() {
      _messages.add(_UserMsg(text));
      _busy = true;
      _input.clear();
    });
    try {
      final result = await _repo.reply(text);
      _messages.add(_CoachMsg(result));
    } on CoachLimitException {
      _messages.add(_NoticeMsg('You have reached the free daily limit. Upgrade to Premium for unlimited coaching.', upgrade: true));
    } on CoachRejectedException catch (e) {
      _messages.add(_NoticeMsg(e.message));
    } catch (_) {
      _messages.add(_NoticeMsg('The coach is unavailable right now. Please try again.'));
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (_scroll.hasClients) {
      _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.black,
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => context.pop()),
        title: Text('AI Coach', style: t.titleLarge?.copyWith(color: AppColors.gold)),
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.all(AppSpacing.l),
              children: [
                if (_messages.isEmpty) ...[
                  Text('How can I help you today?', style: t.headlineMedium),
                  const SizedBox(height: AppSpacing.m),
                  Wrap(spacing: AppSpacing.s, runSpacing: AppSpacing.s, children: [
                    for (final p in _prompts)
                      ActionChip(
                        label: Text(p),
                        onPressed: () => _input.text = '$p ',
                      ),
                  ]),
                ],
                for (final m in _messages) ...[
                  _bubble(m, t),
                  const SizedBox(height: AppSpacing.m),
                ],
                if (_busy) const Center(child: CircularProgressIndicator(color: AppColors.gold)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.m),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 1500,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(hintText: 'Paste a message or ask for help', counterText: ''),
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              GoldButton(label: 'Send', expanded: false, onPressed: _busy ? null : _send),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _bubble(_Msg m, TextTheme t) {
    switch (m) {
      case _UserMsg(:final text):
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
            padding: const EdgeInsets.all(AppSpacing.m + 2),
            decoration: BoxDecoration(gradient: AppColors.goldGradient, borderRadius: BorderRadius.circular(16)),
            child: Text(text, style: const TextStyle(color: Colors.black)),
          ),
        );
      case _NoticeMsg(:final text, :final upgrade):
        return AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(text),
            if (upgrade) ...[
              const SizedBox(height: AppSpacing.m),
              GoldButton(label: 'Upgrade to Premium', onPressed: () => context.push('/paywall')),
            ],
          ]),
        );
      case _CoachMsg(:final result):
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final r in result.replies) ...[
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                TagChip(_styleLabels[r.style] ?? r.style),
                const SizedBox(height: AppSpacing.s),
                SelectableText('“${r.text}”', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w500)),
                const SizedBox(height: AppSpacing.s),
                Text(r.why, style: t.bodySmall),
              ]),
            ),
            const SizedBox(height: AppSpacing.s),
          ],
          if (result.riskNote != null && result.riskNote!.isNotEmpty)
            Text(result.riskNote!, style: t.bodySmall),
        ]);
    }
  }
}
