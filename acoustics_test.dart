import 'dart:math' as math;
import 'dart:typed_data';

import 'package:goldentongue/features/studio/acoustics.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List pcm(double hz, double seconds, double amplitude) {
  final n = (16000 * seconds).round();
  final data = ByteData(n * 2);
  for (var i = 0; i < n; i++) {
    final v = amplitude * math.sin(2 * math.pi * hz * i / 16000);
    data.setInt16(i * 2, (v * 32767).round(), Endian.little);
  }
  return data.buffer.asUint8List();
}

void main() {
  test('wav header is valid and sized correctly', () {
    final body = Uint8List(1000);
    final wav = wavFromPcm16(body);
    expect(wav.length, 1044);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    final bd = ByteData.sublistView(wav);
    expect(bd.getUint32(24, Endian.little), 16000);
    expect(bd.getUint32(40, Endian.little), 1000);
  });

  test('a 200 Hz tone is measured close to 200 Hz', () {
    final a = AcousticAnalyzer()..feed(pcm(200, 1.5, 0.3));
    final m = a.finish();
    expect(m['pitchMedianHz'], inInclusiveRange(190, 210));
    expect(m['pauseRatio'], lessThan(0.1));
  });

  test('silence is counted as pauses and gives no pitch', () {
    final a = AcousticAnalyzer()
      ..feed(pcm(200, 1.0, 0.3))
      ..feed(Uint8List(16000 * 2)); // one second of silence
    final m = a.finish();
    expect(m['pauseRatio'], inInclusiveRange(0.4, 0.6));
    final silent = AcousticAnalyzer()..feed(Uint8List(16000 * 2));
    expect(silent.finish().containsKey('pitchMedianHz'), false);
  });

  test('reset clears earlier data', () {
    final a = AcousticAnalyzer()..feed(pcm(200, 1.0, 0.3));
    a.reset();
    expect(a.finish().isEmpty, true);
  });
}
