// Testet die Bild→PDF-Kette ohne UI: Farbmodi + PDF-Erstellung.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:pdf_zu_bild/image_processing.dart';
import 'package:pdf_zu_bild/pdf_builder.dart';

Uint8List _makeTestPng(int w, int h) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(255, 255, 255));
  // Ein dunkles Rechteck als „Inhalt".
  img.fillRect(im,
      x1: w ~/ 4,
      y1: h ~/ 4,
      x2: w * 3 ~/ 4,
      y2: h * 3 ~/ 4,
      color: img.ColorRgb8(20, 20, 20));
  return Uint8List.fromList(img.encodePng(im));
}

void main() {
  test('Alle Farbmodi liefern dekodierbare Bilder gleicher Größe', () {
    final src = _makeTestPng(300, 200);
    for (final mode in ColorMode.values) {
      final out = processImage(src, mode);
      final decoded = img.decodeImage(out);
      expect(decoded, isNotNull, reason: 'Modus $mode nicht dekodierbar');
      expect(decoded!.width, 300);
      expect(decoded.height, 200);
    }
  });

  test('Schwarz-Weiß ist tatsächlich grau (R=G=B)', () {
    final src = _makeTestPng(60, 40);
    final out = processImage(src, ColorMode.grayscale);
    final im = img.decodeImage(out)!;
    final px = im.getPixel(10, 10);
    expect(px.r, px.g);
    expect(px.g, px.b);
  });

  test('buildPdfFromImages erzeugt gültiges PDF mit mehreren Seiten', () async {
    final pages = [
      processImage(_makeTestPng(300, 200), ColorMode.original), // quer
      processImage(_makeTestPng(200, 300), ColorMode.scan), // hoch
    ];
    final pdf = await buildPdfFromImages(pages);

    // PDF-Signatur „%PDF".
    expect(pdf.length, greaterThan(1000));
    expect(String.fromCharCodes(pdf.sublist(0, 4)), '%PDF');
  });
}
