import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Baut aus einer Liste von Bild-Bytes ein PDF (eine Seite pro Bild).
/// Querformat-Bilder kommen auf A4-quer, sonst A4-hoch; das Bild wird
/// eingepasst (kein Beschnitt).
Future<Uint8List> buildPdfFromImages(List<Uint8List> images) async {
  final doc = pw.Document();
  for (final bytes in images) {
    final image = pw.MemoryImage(bytes);
    final w = image.width ?? 1;
    final h = image.height ?? 1;
    final format = w > h ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;
    doc.addPage(
      pw.Page(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(8),
        build: (ctx) =>
            pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
      ),
    );
  }
  return doc.save();
}
