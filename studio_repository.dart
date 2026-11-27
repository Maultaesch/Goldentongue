import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/data_providers.dart';

class PremiumRequiredException implements Exception {}

class LimitReachedException implements Exception {}

class StudioException implements Exception {
  final String message;
  const StudioException(this.message);
}

class StudioRepository {
  Future<Map<String, dynamic>> _invoke(String fn, Map<String, dynamic> body) async {
    try {
      final res = await sb.functions.invoke(fn, body: body);
      return Map<String, dynamic>.from(res.data as Map);
    } on FunctionException catch (e) {
      if (e.status == 402) throw PremiumRequiredException();
      if (e.status == 429) throw LimitReachedException();
      final d = e.details;
      throw StudioException(d is Map && d['error'] is String ? d['error'] as String : 'Something went wrong.');
    }
  }

  /// Uploads the recording to the private `voice` bucket, then asks the server to analyze it.
  Future<Map<String, dynamic>> analyzeVoice(Uint8List wavBytes, int seconds, {Map<String, dynamic>? metrics}) async {
    final path = '$uid/${DateTime.now().millisecondsSinceEpoch}.wav';
    await sb.storage.from('voice').uploadBinary(path, wavBytes, fileOptions: const FileOptions(contentType: 'audio/wav'));
    return _invoke('voice-analyze', {'audio_path': path, 'seconds': seconds, if (metrics != null) 'metrics': metrics});
  }

  Future<Map<String, dynamic>> simStart(String persona, String mode) =>
      _invoke('simulator', {'action': 'start', 'persona': persona, 'mode': mode});

  Future<Map<String, dynamic>> simTurn(String sessionId, String message) =>
      _invoke('simulator', {'action': 'turn', 'session_id': sessionId, 'message': message});

  Future<Map<String, dynamic>> simEnd(String sessionId) =>
      _invoke('simulator', {'action': 'end', 'session_id': sessionId});

  Future<Map<String, dynamic>> evaluateExercise(String exerciseId, String answer) =>
      _invoke('exercise-evaluate', {'exercise_id': exerciseId, 'answer': answer});

  Future<Map<String, dynamic>> createBlueprint() => _invoke('blueprint', {});

  Future<Map<String, dynamic>?> latestBlueprint() async {
    final row = await sb.from('blueprints').select('data').order('created_at', ascending: false).limit(1).maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row['data'] as Map);
  }
}
