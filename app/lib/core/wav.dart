// Genera un WAV (PCM 16 bits, mono) con una secuencia de tonos senoidales.
// Puro Dart: se puede probar sin Flutter.
import 'dart:math' as math;
import 'dart:typed_data';

Uint8List generarWav(
  List<(int, int)> tonos, {
  int pausaMs = 60,
  int sampleRate = 22050,
  double volumen = 0.6,
}) {
  final muestras = <int>[];
  const rampaMs = 8; // evita "clics" al inicio/fin de cada tono
  for (var t = 0; t < tonos.length; t++) {
    final (freq, ms) = tonos[t];
    final n = sampleRate * ms ~/ 1000;
    final rampa = sampleRate * rampaMs ~/ 1000;
    for (var i = 0; i < n; i++) {
      var env = 1.0;
      if (i < rampa) env = i / rampa;
      if (i > n - rampa) env = (n - i) / rampa;
      final v = math.sin(2 * math.pi * freq * i / sampleRate) * volumen * env;
      muestras.add((v * 32767).round().clamp(-32768, 32767));
    }
    if (t < tonos.length - 1) {
      muestras.addAll(List.filled(sampleRate * pausaMs ~/ 1000, 0));
    }
  }

  final dataLen = muestras.length * 2;
  final b = ByteData(44 + dataLen);
  void str(int off, String s) {
    for (var i = 0; i < s.length; i++) {
      b.setUint8(off + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  b.setUint32(4, 36 + dataLen, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  b.setUint32(16, 16, Endian.little); // tamaño del bloque fmt
  b.setUint16(20, 1, Endian.little); // PCM
  b.setUint16(22, 1, Endian.little); // mono
  b.setUint32(24, sampleRate, Endian.little);
  b.setUint32(28, sampleRate * 2, Endian.little); // byte rate
  b.setUint16(32, 2, Endian.little); // block align
  b.setUint16(34, 16, Endian.little); // bits por muestra
  str(36, 'data');
  b.setUint32(40, dataLen, Endian.little);
  for (var i = 0; i < muestras.length; i++) {
    b.setInt16(44 + i * 2, muestras[i], Endian.little);
  }
  return b.buffer.asUint8List();
}
