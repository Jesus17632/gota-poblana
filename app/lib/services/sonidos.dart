// Alertas sonoras y hápticas de la app (duplican los pitidos del equipo).
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/device_constants.dart';
import '../core/wav.dart';
import 'wav_source.dart';

enum Tono { inicio, fin, error }

Tono? tonoDe(String? nombre) => switch (nombre) {
      'inicio' => Tono.inicio,
      'fin' => Tono.fin,
      'error' => Tono.error,
      _ => null,
    };

class Sonidos {
  AudioPlayer? _player;
  final Map<Tono, Source> _cache = {};

  static List<(int, int)> secuencia(Tono t) => switch (t) {
        Tono.inicio => DeviceConst.tonosInicio,
        Tono.fin => DeviceConst.tonosFin,
        Tono.error => DeviceConst.tonosError,
      };

  Future<void> tocar(Tono t) async {
    try {
      final player = _player ??= AudioPlayer();
      final src = _cache[t] ??= await fuenteWav(
        generarWav(secuencia(t), pausaMs: DeviceConst.pausaEntreTonosMs),
        'agua_tono_${t.name}.wav',
      );
      await player.stop();
      await player.play(src);
    } catch (e) {
      // Sin audio en esta plataforma: la alerta visual sigue funcionando.
      debugPrint('No se pudo reproducir el tono: $e');
    }
  }

  Future<void> vibrar(Tono t) async {
    try {
      if (t == Tono.error) {
        await HapticFeedback.heavyImpact();
      } else {
        await HapticFeedback.mediumImpact();
      }
    } catch (_) {
      // Sin háptica (escritorio/web): no pasa nada.
    }
  }

  Future<void> dispose() async {
    await _player?.dispose();
  }
}
