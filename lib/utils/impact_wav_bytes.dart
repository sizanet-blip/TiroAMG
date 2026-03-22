import 'dart:math';
import 'dart:typed_data';

/// Genera WAV PCM 16-bit mono en memoria (para Windows / desktop donde `SystemSound` no suena).
Uint8List buildImpactWavBytes({
  required double frequencyHz,
  required int durationMs,
  int sampleRate = 22050,
}) {
  final n = (sampleRate * durationMs / 1000).round().clamp(1, 22050 * 2);
  final samples = Int16List(n);
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    final env = 1.0 - (i / n); // decay
    final s = sin(2 * pi * frequencyHz * t) * 0.22 * env;
    samples[i] = (s * 32767).round().clamp(-32768, 32767);
  }
  return _pcm16MonoToWav(samples, sampleRate);
}

Uint8List _pcm16MonoToWav(Int16List samples, int sampleRate) {
  final dataSize = samples.length * 2;
  final chunkSize = 36 + dataSize;
  final out = Uint8List(44 + dataSize);
  final bd = ByteData.sublistView(out);

  var o = 0;
  void writeAscii4(String s) {
    for (var i = 0; i < 4; i++) {
      bd.setUint8(o + i, s.codeUnitAt(i));
    }
    o += 4;
  }

  writeAscii4('RIFF');
  bd.setUint32(o, chunkSize, Endian.little);
  o += 4;
  writeAscii4('WAVE');
  writeAscii4('fmt ');
  bd.setUint32(o, 16, Endian.little);
  o += 4;
  bd.setUint16(o, 1, Endian.little);
  o += 2;
  bd.setUint16(o, 1, Endian.little);
  o += 2;
  bd.setUint32(o, sampleRate, Endian.little);
  o += 4;
  bd.setUint32(o, sampleRate * 2, Endian.little);
  o += 4;
  bd.setUint16(o, 2, Endian.little);
  o += 2;
  bd.setUint16(o, 16, Endian.little);
  o += 2;
  writeAscii4('data');
  bd.setUint32(o, dataSize, Endian.little);
  o += 4;

  for (var i = 0; i < samples.length; i++) {
    bd.setInt16(o, samples[i], Endian.little);
    o += 2;
  }
  return out;
}
