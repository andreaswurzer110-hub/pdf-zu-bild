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

/// „Eingescannt"-Look wie von einem echten Flachbett-Scanner:
/// gleichmäßig weißes Papier (Schatten/ungleiches Licht raus), kräftiger,
/// scharfer Text. Kernstück ist die Beleuchtungs-Korrektur (Flat-Field):
/// Das Foto wird durch seinen eigenen, stark unscharfen „Hintergrund" geteilt,
/// wodurch ungleichmäßige Ausleuchtung verschwindet und Papier sauber weiß wird.
img.Image _scanLook(img.Image src) {
  final gray = img.grayscale(src);
  final w = gray.width;
  final h = gray.height;

  // 1. Beleuchtung schätzen: stark verkleinern (Mittelung), glätten, wieder
  //    hochskalieren. Das ergibt den lokalen Papier-/Lichthintergrund.
  final smallW = (w ~/ 8).clamp(1, w);
  final smallH = (h ~/ 8).clamp(1, h);
  var bg = img.copyResize(gray,
      width: smallW, height: smallH, interpolation: img.Interpolation.average);
  bg = img.gaussianBlur(bg, radius: 3);
  bg = img.copyResize(bg,
      width: w, height: h, interpolation: img.Interpolation.linear);

  // 2. Flat-Field-Division + Tonwertkurve.
  //    ratio = Pixel / Hintergrund  (Papier ≈ 1 → weiß, Text < 1 → dunkel)
  const blackPoint = 0.50; // Verhältnis darunter → reines Schwarz
  const whitePoint = 0.93; // Verhältnis darüber → reines Papierweiß
  final out = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final g = gray.getPixel(x, y).luminance.toDouble();
      final b = bg.getPixel(x, y).luminance.toDouble();
      final ratio = b <= 1 ? 1.0 : (g / b);

      var t = (ratio - blackPoint) / (whitePoint - blackPoint);
      if (t < 0) t = 0;
      if (t > 1) t = 1;
      // Weiche S-Kurve (smoothstep): Text satt, Papier sauber, Kanten weich.
      final v = (255.0 * (t * t * (3 - 2 * t))).round();
      out.setPixelRgb(x, y, v, v, v);
    }
  }

  // 3. Leichtes Schärfen – wie der feine Kontrast eines echten Scanners.
  return img.convolution(out,
      filter: [0, -1, 0, -1, 5, -1, 0, -1, 0], div: 1, offset: 0);
}
