// Integrationstest: prueft das echte pdfium-Rendering (pdfrx) auf der
// Zielplattform. Laedt das Test-PDF, rendert Seiten mit 300 DPI, prueft die
// Pixelmasse und dass PNG-/JPEG-Dateien tatsaechlich geschrieben werden.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';

Uint8List _encode(img.Image image, {required bool png, int quality = 92}) =>
    png ? img.encodePng(image) : img.encodeJpg(image, quality: quality);

img.Image _toImage(PdfImage r) => img.Image.fromBytes(
      width: r.width,
      height: r.height,
      bytes: r.pixels.buffer,
      order: img.ChannelOrder.bgra,
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Pfad zum Test-PDF (per --dart-define uebergeben).
  const pdfPath = String.fromEnvironment('TEST_PDF');

  setUpAll(() async => pdfrxFlutterInitialize());

  test('PDF hat 3 Seiten und rendert mit 300 DPI scharf', () async {
    expect(pdfPath.isNotEmpty, true,
        reason: 'TEST_PDF muss per --dart-define gesetzt sein');
    expect(File(pdfPath).existsSync(), true, reason: 'Test-PDF fehlt: $pdfPath');

    final doc = await PdfDocument.openFile(pdfPath);
    expect(doc.pages.length, 3, reason: 'erwartet 3 Seiten');

    const dpi = 300;
    final page = doc.pages[0];

    // A4 = 595 x 842 pt. Bei 300 DPI: ~2479 x 3508 px.
    final expectedW = (page.width * dpi / 72).round();
    final expectedH = (page.height * dpi / 72).round();

    final rendered = await page.render(
      fullWidth: page.width * dpi / 72,
      fullHeight: page.height * dpi / 72,
      backgroundColor: 0xFFFFFFFF,
    );
    expect(rendered, isNotNull);
    // pdfium schneidet die Zielmaße ab (.toInt()), daher ±1 px Toleranz.
    expect(rendered!.width, closeTo(expectedW, 1));
    expect(rendered.height, closeTo(expectedH, 1));

    final png = _encode(_toImage(rendered), png: true);
    rendered.dispose();
    await doc.dispose();

    // PNG-Magic-Bytes pruefen.
    expect(png.length > 1000, true, reason: 'PNG zu klein');
    expect(png[0], 0x89);
    expect(png[1], 0x50); // 'P'

    // Datei tatsaechlich schreiben (wie die App es tut).
    final out = File('${Directory.systemTemp.path}/itest_seite1.png');
    await out.writeAsBytes(png);
    expect(out.existsSync(), true);
    expect(out.lengthSync(), png.length);

    // ignore: avoid_print
    print('OK: Seite 1 gerendert -> $expectedW x $expectedH px, '
        '${png.length} bytes, Datei: ${out.path}');
  });

  test('JPEG-Ausgabe funktioniert', () async {
    final doc = await PdfDocument.openFile(pdfPath);
    final page = doc.pages[1];
    final rendered = await page.render(
      fullWidth: page.width * 300 / 72,
      fullHeight: page.height * 300 / 72,
      backgroundColor: 0xFFFFFFFF,
    );
    expect(rendered, isNotNull);
    final jpg = _encode(_toImage(rendered!), png: false, quality: 92);
    rendered.dispose();
    await doc.dispose();

    // JPEG-Magic-Bytes: FF D8.
    expect(jpg[0], 0xFF);
    expect(jpg[1], 0xD8);
    // ignore: avoid_print
    print('OK: JPEG Seite 2 -> ${jpg.length} bytes');
  });
}
