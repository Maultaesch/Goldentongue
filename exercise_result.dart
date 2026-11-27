class CriterionResult {
  final String name;
  final int score;
  final String comment;
  const CriterionResult(this.name, this.score, this.comment);
}

String scoreLabel(int score) {
  if (score >= 85) return 'Excellent';
  if (score >= 70) return 'Strong';
  if (score >= 50) return 'Developing';
  return 'Keep practicing';
}

/// Parsed answer of the `exercise-evaluate` function. Tolerates missing fields and numeric types.
class ExerciseResult {
  final int score;
  final List<CriterionResult> criteria;
  final String good;
  final String improve;
  final String example;
  const ExerciseResult({required this.score, required this.criteria, required this.good, required this.improve, required this.example});

  String get label => scoreLabel(score);

  static int _score(dynamic v) => (v is num ? v.round() : 0).clamp(0, 100);

  factory ExerciseResult.fromJson(Map<String, dynamic> json) => ExerciseResult(
        score: _score(json['score']),
        criteria: [
          for (final c in (json['criteria'] as List? ?? const []))
            if (c is Map) CriterionResult('${c['name'] ?? ''}', _score(c['score']), '${c['comment'] ?? ''}'),
        ],
        good: '${json['good'] ?? ''}',
        improve: '${json['improve'] ?? ''}',
        example: '${json['example'] ?? ''}',
      );
}
