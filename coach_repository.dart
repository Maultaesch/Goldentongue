import 'package:supabase_flutter/supabase_flutter.dart';

class CoachReply {
  final String style;
  final String text;
  final String why;
  const CoachReply(this.style, this.text, this.why);
}

class CoachResult {
  final List<CoachReply> replies;
  final String? riskNote;
  const CoachResult(this.replies, this.riskNote);
}

class CoachLimitException implements Exception {}

class CoachRejectedException implements Exception {
  final String message;
  const CoachRejectedException(this.message);
}

class CoachRepository {
  Future<CoachResult> reply(String message, {String? context}) async {
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'coach',
        body: {'message': message, if (context != null) 'context': context},
      );
      final data = Map<String, dynamic>.from(res.data as Map);
      final replies = [
        for (final r in (data['replies'] as List? ?? const []))
          CoachReply(
            '${r['style']}',
            '${r['text']}',
            '${r['why']}',
          ),
      ];
      return CoachResult(replies, data['risk_note'] as String?);
    } on FunctionException catch (e) {
      if (e.status == 429) throw CoachLimitException();
      if (e.status == 422) {
        final details = e.details;
        final msg = details is Map && details['error'] is String
            ? details['error'] as String
            : 'This request cannot be answered.';
        throw CoachRejectedException(msg);
      }
      rethrow;
    }
  }
}
