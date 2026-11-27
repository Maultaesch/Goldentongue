import 'package:goldentongue/core/ranks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rank index follows the XP thresholds', () {
    expect(rankIndexFor(0), 0);
    expect(rankIndexFor(99), 0);
    expect(rankIndexFor(100), 1);
    expect(rankIndexFor(599), 2);
    expect(rankIndexFor(2500), ranks.length - 1);
    expect(rankIndexFor(99999), ranks.length - 1);
  });

  test('rank progress runs from 0 to 1 and is 1 at the top rank', () {
    expect(rankProgress(0), 0);
    expect(rankProgress(50), closeTo(0.5, 0.001));
    expect(rankProgress(100), 0);
    expect(rankProgress(5000), 1);
  });
}
