// Integrationstest: prueft das echte pdfium-Rendering auf der Zielplattform.
// Laedt das Test-PDF, rendert Seiten mit 300 DPI und prueft die Pixelmasse
// sowie dass PNG-/JPEG-Dateien tatsaechlich geschrieben werden.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfx/pdfx.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Pfad zum Test-PDF (per --dart-define uebergeben).
  const pdfPath = String.fromEnvironment('TEST_PDF');

  test('PDF hat 3 Seiten und rendert mit 300 DPI scharf', () async {
    expect(pdfPath.isNotEmpty, true,
        reason: 'TEST_PDF muss per --dart-define gesetzt sein');
    expect(File(pdfPath).existsSync(), true, reason: 'Test-PDF fehlt: $pdfPath');

    final doc = await PdfDocument.openFile(pdfPath);
    expect(doc.pagesCount, 3, reason: 'erwartet 3 Seiten');

    const dpi = 300;
    final page = await doc.getPage(1);

    // A4 = 595 x 842 pt. Bei 300 DPI: ~2479 x 3508 px.
    final expectedW = (page.width * dpi / 72).round();
    final expectedH = (page.height * dpi / 72).round();

    final png = await page.render(
      width: expectedW.toDouble(),
      height: expectedH.toDouble(),
      format: PdfPageImageFormat.png,
      backgroundColor: '#FFFFFF',
    );
    await page.close();

    expect(png, isNotNull);
    expect(png!.width, expectedW);
    expect(png.height, expectedH);
    // PNG-Magic-Bytes pruefen.
    expect(png.bytes.length > 1000, true, reason: 'PNG zu klein');
    expect(png.bytes[0], 0x89);
    expect(png.bytes[1], 0x50); // 'P'

    // Datei tatsaechlich schreiben (wie die App es tut).
    final out = File('${Directory.systemTemp.path}/itest_seite1.png');
    await out.writeAsBytes(png.bytes);
    expect(out.existsSync(), true);
    expect(out.lengthSync(), png.bytes.length);

    await doc.close();

    // Pixelmasse fuer das Protokoll ausgeben.
    // ignore: avoid_print
    print('OK: Seite 1 gerendert -> ${png.width} x ${png.height} px, '
        '${png.bytes.length} bytes, Datei: ${out.path}');
  });

  test('JPEG-Ausgabe funktioniert', () async {
    final doc = await PdfDocument.openFile(pdfPath);
    final page = await doc.getPage(2);
    final jpg = await page.render(
      width: page.width * 300 / 72,
      height: page.height * 300 / 72,
      format: PdfPageImageFormat.jpeg,
      backgroundColor: '#FFFFFF',
      quality: 92,
    );
    await page.close();
    await doc.close();

    expect(jpg, isNotNull);
    // JPEG-Magic-Bytes: FF D8.
    expect(jpg!.bytes[0], 0xFF);
    expect(jpg.bytes[1], 0xD8);
    // ignore: avoid_print
    print('OK: JPEG Seite 2 -> ${jpg.width} x ${jpg.height} px, '
        '${jpg.bytes.length} bytes');
  });
}
