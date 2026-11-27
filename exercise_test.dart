import 'package:goldentongue/features/practice/exercise_result.dart';
import 'package:goldentongue/features/practice/practice_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExerciseResult', () {
    test('parses a full result and clamps scores', () {
      final r = ExerciseResult.fromJson({
        'score': 130,
        'criteria': [
          {'name': 'Curious', 'score': 80.4, 'comment': 'Good'},
          {'name': 'Meaning', 'score': -5},
        ],
        'good': 'g',
        'improve': 'i',
        'example': 'e',
      });
      expect(r.score, 100);
      expect(r.criteria.length, 2);
      expect(r.criteria[0].score, 80);
      expect(r.criteria[1].score, 0);
      expect(r.criteria[1].comment, '');
      expect(r.label, 'Excellent');
    });

    test('tolerates missing fields', () {
      final r = ExerciseResult.fromJson({});
      expect(r.score, 0);
      expect(r.criteria, isEmpty);
      expect(r.good, '');
      expect(r.label, 'Keep practicing');
    });

    test('score labels follow the thresholds', () {
      expect(scoreLabel(49), 'Keep practicing');
      expect(scoreLabel(50), 'Developing');
      expect(scoreLabel(70), 'Strong');
      expect(scoreLabel(85), 'Excellent');
    });
  });

  group('ExerciseScreen', () {
    const exercise = {
      'id': 'ex1',
      'title': 'Follow up on a dream',
      'prompt': 'She says she secretly wants to open a bakery.',
      'criteria': ['Shows genuine curiosity', 'Asks about meaning', 'Encourages without overpromising'],
    };

    testWidgets('shows the situation and the criteria', (tester) async {
      await tester.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: const ExerciseScreen(exercise: exercise)));
      expect(find.text('Situation'), findsOneWidget);
      expect(find.textContaining('secretly wants to open a bakery'), findsOneWidget);
      expect(find.textContaining('Shows genuine curiosity'), findsOneWidget);
    });

    testWidgets('short answers are rejected locally without calling the server', (tester) async {
      await tester.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: const ExerciseScreen(exercise: exercise)));
      await tester.enterText(find.byType(TextField), 'too short');
      await tester.ensureVisible(find.text('Get my evaluation'));
      await tester.tap(find.text('Get my evaluation'));
      await tester.pump();
      expect(find.textContaining('at least a couple of sentences'), findsOneWidget);
    });
  });
}
