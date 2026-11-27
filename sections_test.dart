import 'package:goldentongue/features/sections/sections_screens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('section cards are read from database rows', () {
    final item = SectionItem.fromRow({
      'title': 'Dreams',
      'tags': ['18 questions', 'Easy'],
      'detail_label': 'Sample questions',
      'details': ['What would you do if you could not fail?'],
      'route': null,
    });
    expect(item.title, 'Dreams');
    expect(item.tags, ['18 questions', 'Easy']);
    expect(item.details.length, 1);
    expect(item.route, isNull);
  });

  test('missing fields do not crash', () {
    final item = SectionItem.fromRow({'title': 'Voice Analysis', 'route': '/studio/voice'});
    expect(item.tags, isEmpty);
    expect(item.detailLabel, '');
    expect(item.route, '/studio/voice');
  });
}
