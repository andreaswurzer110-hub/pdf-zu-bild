import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Farb-/Aufbereitungsmodus für Bild → PDF.
enum ColorMode {
  original('Original'),
  grayscale('Schwarz-Weiß'),
  scan('Scan');

  const ColorMode(this.label);
  final String label;
}

/// Wendet den gewählten Modus auf ein Bild an und gibt JPEG-Bytes zurück.
/// Läuft in einem Isolate-tauglichen, reinen Dart-Pfad (keine Flutter-Abhängigkeit).
Uint8List processImage(Uint8List input, ColorMode mode, {int jpegQuality = 90}) {
  final decoded = img.decodeImage(input);
  if (decoded == null) return input;

  img.Image out;
  switch (mode) {
    case ColorMode.original:
      out = decoded;
      break;
    case ColorMode.grayscale:
      out = img.grayscale(decoded);
      break;
    case ColorMode.scan:
      out = _scanLook(decoded);
      break;
  }
  return img.encodeJpg(out, quality: jpegQuality);
}

/// „Eingescannt"-Look: Graustufen, Kontrast anheben, Hintergrund aufhellen,
/// damit Papier weiß und Text kräftig wirkt.
img.Image _scanLook(img.Image src) {
  var im = img.grayscale(src);
  // Helligkeit/Kontrast anheben.
  im = img.adjustColor(im, contrast: 1.35, brightness: 1.05);
  // Tonwerte spreizen.
  im = img.normalize(im, min: 0, max: 255);

  // Weißpunkt hochziehen: helle Bereiche zu reinem Weiß, dunkle abdunkeln.
  const whiteCut = 175; // ab hier -> Papierweiß
  const blackBoost = 90; // darunter -> kräftig dunkler
  for (final p in im) {
    final l = p.luminance.toInt();
    if (l >= whiteCut) {
      p.setRgb(255, 255, 255);
    } else if (l <= blackBoost) {
      final v = (l * 0.6).round();
      p.setRgb(v, v, v);
    }
  }
  return im;
}
