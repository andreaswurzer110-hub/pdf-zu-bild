// Erzeugt ein 3-seitiges A4-Test-PDF für die Integrationstests.
// Aufruf:  dart run tool/make_test_pdf.dart <ausgabepfad>
import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Future<void> main(List<String> args) async {
  final out = args.isNotEmpty ? args.first : 'test_3seiten.pdf';
  final doc = pw.Document();
  for (var i = 1; i <= 3; i++) {
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Center(
          child: pw.Text('Seite $i', style: pw.TextStyle(fontSize: 96)),
        ),
      ),
    );
  }
  await File(out).writeAsBytes(await doc.save());
  stdout.writeln('Geschrieben: $out');
}
