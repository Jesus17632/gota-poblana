import 'dart:convert';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

Future<Source> fuenteWav(Uint8List bytes, String nombre) async =>
    UrlSource('data:audio/wav;base64,${base64Encode(bytes)}');
