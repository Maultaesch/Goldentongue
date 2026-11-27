import 'dart:math' as math;
import 'dart:typed_data';

const _sampleRate = 16000;

/// Builds a mono 16 kHz, 16-bit WAV file from raw PCM bytes.
Uint8List wavFromPcm16(Uint8List pcm) {
  final h = ByteData(44);
  void tag(int offset, String text) {
    for (var i = 0; i < 4; i++) {
      h.setUint8(offset + i, text.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  h.setUint32(4, 36 + pcm.length, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  h.setUint32(16, 16, Endian.little);
  h.setUint16(20, 1, Endian.little); // PCM
  h.setUint16(22, 1, Endian.little); // mono
  h.setUint32(24, _sampleRate, Endian.little);
  h.setUint32(28, _sampleRate * 2, Endian.little);
  h.setUint16(32, 2, Endian.little);
  h.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  h.setUint32(40, pcm.length, Endian.little);
  return (BytesBuilder(copy: false)
        ..add(h.buffer.asUint8List())
        ..add(pcm))
      .toBytes();
}

/// Measures pitch, pauses and energy from a 16 kHz mono PCM16 stream on the device.
class AcousticAnalyzer {
  static const _frame = 1024; // 64 ms
  static const _silence = 0.012;

  final _pending = <double>[];
  final _f0 = <double>[];
  final _rms = <double>[];
  int _silent = 0;
  int _frames = 0;
  double lastRms = 0;

  void reset() {
    _pending.clear();
    _f0.clear();
    _rms.clear();
    _silent = 0;
    _frames = 0;
    lastRms = 0;
  }

  void feed(Uint8List chunk) {
    final bd = ByteData.sublistView(chunk);
    for (var i = 0; i + 1 < chunk.length; i += 2) {
      _pending.add(bd.getInt16(i, Endian.little) / 32768.0);
    }
    while (_pending.length >= _frame) {
      _analyze(_pending.sublist(0, _frame));
      _pending.removeRange(0, _frame);
    }
  }

  void _analyze(List<double> b) {
    var e = 0.0;
    for (final v in b) {
      e += v * v;
    }
    final rms = math.sqrt(e / b.length);
    lastRms = rms;
    _frames++;
    _rms.add(rms);
    if (rms < _silence) {
      _silent++;
      return;
    }
    final lo = _sampleRate ~/ 400, hi = _sampleRate ~/ 70;
    var best = 0.0;
    var bestLag = 0;
    for (var l = lo; l <= hi; l++) {
      var c = 0.0;
      for (var i = 0; i < b.length - l; i += 2) {
        c += b[i] * b[i + l];
      }
      if (c > best) {
        best = c;
        bestLag = l;
      }
    }
    if (bestLag > 0 && best / (e / 2) > 0.35) _f0.add(_sampleRate / bestLag);
  }

  double _std(List<double> a) {
    if (a.isEmpty) return 0;
    final m = a.reduce((x, y) => x + y) / a.length;
    return math.sqrt(a.map((v) => (v - m) * (v - m)).reduce((x, y) => x + y) / a.length);
  }

  /// Keys match the server: pauseRatio, energyVariation, pitchMedianHz, pitchRangeSemitones.
  Map<String, dynamic> finish() {
    final out = <String, dynamic>{};
    if (_frames > 0) {
      out['pauseRatio'] = double.parse((_silent / _frames).toStringAsFixed(2));
      out['energyVariation'] = double.parse(_std(_rms).toStringAsFixed(3));
    }
    if (_f0.length > 10) {
      final s = [..._f0]..sort();
      double q(double p) => s[((s.length - 1) * p).floor()];
      double st(double hz) => 12 * (math.log(hz) / math.ln2);
      out['pitchMedianHz'] = q(.5).round();
      out['pitchRangeSemitones'] = double.parse((st(q(.9)) - st(q(.1))).toStringAsFixed(1));
    }
    return out;
  }
}
