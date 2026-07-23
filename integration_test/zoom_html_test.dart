// Integrationstest: erzeugt aus dem Test-PDF eine Zoom-HTML (Kachel-Pyramide)
// und prueft Struktur/Inhalt der Datei. TEST_PDF per --dart-define setzen.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdf_zu_bild/zoom_html.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const pdfPath = String.fromEnvironment('TEST_PDF');

  setUpAll(() async => pdfrxFlutterInitialize());

  // Grosszuegiges Timeout: mit einer echten Riesen-PDF (Poster) dauert die
  // Pyramide je nach Rechner mehrere Minuten.
  test('Zoom-HTML wird erzeugt und enthaelt Viewer + Kacheln',
      timeout: const Timeout(Duration(minutes: 10)), () async {
    expect(pdfPath.isNotEmpty, true,
        reason: 'TEST_PDF muss per --dart-define gesetzt sein');
    expect(File(pdfPath).existsSync(), true, reason: 'Test-PDF fehlt: $pdfPath');

    final doc = await PdfDocument.openFile(pdfPath);
    final page = doc.pages[0];
    final out = '${Directory.systemTemp.path}/itest_zoom.html';

    final statuses = <String>[];
    double lastProgress = -1;
    var progressMonoton = true;

    final ok = await writeZoomHtml(
      page: page,
      outPath: out,
      title: 'Test <Titel> & Co',
      dpi: 300,
      stripBudgetBytes: 64 * 1024 * 1024,
      onProgress: (status, frac) {
        statuses.add(status);
        if (frac < lastProgress) progressMonoton = false;
        lastProgress = frac;
      },
    );
    await doc.dispose();

    expect(ok, true, reason: 'writeZoomHtml meldet Abbruch/Fehler');
    final f = File(out);
    expect(f.existsSync(), true);
    final html = f.readAsStringSync();

    // Grundstruktur
    expect(html.startsWith('<!DOCTYPE html>'), true);
    expect(html.contains('const META = {'), true);
    expect(html.contains('const TILES = {'), true);
    expect(html.trimRight().endsWith('</html>'), true);
    // Titel HTML-escaped
    expect(html.contains('Test &lt;Titel&gt; &amp; Co'), true);
    // Kacheln der hoechsten Stufe vorhanden (Stufe >= 2 bei A4/300dpi)
    expect(html.contains('"0/0_0":"'), true);
    expect(RegExp(r'"\d+/\d+_\d+":"[A-Za-z0-9+/]+=*"').hasMatch(html), true);
    // JPEG-Magic in Base64 beginnt mit /9j/
    expect(html.contains(':"/9j/'), true);
    // Fortschritt lief monoton bis 1.0
    expect(progressMonoton, true);
    expect(lastProgress, 1.0);
    expect(statuses.isNotEmpty, true);

    // ignore: avoid_print
    print('OK: Zoom-HTML ${f.lengthSync()} bytes, '
        '${statuses.length} Fortschritts-Meldungen');
  });

  test('Abbruch raeumt die halbe Datei weg', () async {
    final doc = await PdfDocument.openFile(pdfPath);
    final page = doc.pages[0];
    final out = '${Directory.systemTemp.path}/itest_zoom_cancel.html';

    var calls = 0;
    final ok = await writeZoomHtml(
      page: page,
      outPath: out,
      title: 'Abbruch',
      dpi: 300,
      stripBudgetBytes: 8 * 1024 * 1024,
      // Nach ein paar Streifen abbrechen.
      isCancelled: () => ++calls > 6,
    );
    await doc.dispose();

    expect(ok, false);
    expect(File(out).existsSync(), false,
        reason: 'abgebrochene Datei muss geloescht sein');
  });
}
