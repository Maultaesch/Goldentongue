import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient get sb => Supabase.instance.client;
String get uid => sb.auth.currentUser!.id;

String _today() => DateTime.now().toIso8601String().substring(0, 10);

final gamificationProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final row = await sb.from('gamification').select().eq('user_id', uid).maybeSingle();
  return row ?? {'xp': 0, 'streak': 0};
});

/// Latest score per skill: confidence, communication, flirting,
/// deep_talk, articulation, charisma, business.
final skillScoresProvider = FutureProvider.autoDispose<Map<String, int>>((ref) async {
  final rows = await sb
      .from('skill_scores')
      .select('skill,score')
      .eq('user_id', uid)
      .order('measured_at', ascending: false);
  final out = <String, int>{};
  for (final r in rows) {
    out.putIfAbsent(r['skill'] as String, () => r['score'] as int);
  }
  return out;
});

final dailyChallengeProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final rows = await sb.from('challenges').select().order('text');
  if (rows.isEmpty) return null;
  final now = DateTime.now();
  final dayOfYear = now.difference(DateTime(now.year)).inDays;
  return rows[dayOfYear % rows.length];
});

final todayDoneProvider = FutureProvider.autoDispose<bool>((ref) async {
  final row = await sb
      .from('user_challenges')
      .select('id')
      .eq('user_id', uid)
      .eq('day', _today())
      .maybeSingle();
  return row != null;
});

final completionsProvider =
    FutureProvider.autoDispose.family<int, int>((ref, days) async {
  final from = DateTime.now().subtract(Duration(days: days - 1));
  final rows = await sb
      .from('user_challenges')
      .select('id')
      .eq('user_id', uid)
      .gte('day', from.toIso8601String().substring(0, 10));
  return rows.length;
});

Future<void> completeChallenge(String challengeId, int result) =>
    sb.rpc('complete_challenge', params: {'p_challenge_id': challengeId, 'p_result': result});
