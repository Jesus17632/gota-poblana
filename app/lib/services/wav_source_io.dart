import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

Future<Source> fuenteWav(Uint8List bytes, String nombre) async {
  final f = File('${Directory.systemTemp.path}${Platform.pathSeparator}$nombre');
  await f.writeAsBytes(bytes, flush: true);
  return DeviceFileSource(f.path);
}
