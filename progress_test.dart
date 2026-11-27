import 'package:goldentongue/features/progress/progress_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 4);
  DateTime ago(int days) => now.subtract(Duration(days: days));

  test('delta needs at least two points', () {
    expect(weeklyDelta([], now: now), isNull);
    expect(weeklyDelta([(ago(1), 50)], now: now), isNull);
  });

  test('delta compares with the last score at least a week old', () {
    final history = [(ago(20), 40), (ago(9), 50), (ago(3), 58), (ago(0), 62)];
    expect(weeklyDelta(history, now: now), 12); // 62 - 50
  });

  test('delta falls back to the first score when the history is short', () {
    final history = [(ago(3), 50), (ago(0), 56)];
    expect(weeklyDelta(history, now: now), 6);
  });
}
