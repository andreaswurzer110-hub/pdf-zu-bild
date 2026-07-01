// Prueft, dass der PDF-Reader (pdfrx PdfViewer) eine PDF laedt und anzeigt.
// Ausfuehren: flutter test integration_test/reader_test.dart -d windows --dart-define=TEST_PDF=...

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';

import 'package:pdf_zu_bild/pages/pdf_reader_page.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const pdfPath = String.fromEnvironment('TEST_PDF');

  setUpAll(() async => pdfrxFlutterInitialize());

  testWidgets('Reader laedt PDF und zeigt Seitenzahl', (tester) async {
    expect(pdfPath.isNotEmpty, true, reason: 'TEST_PDF fehlt');

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: PdfReaderPage(path: pdfPath))),
    );

    // Dem Reader Zeit zum Laden/Rendern geben.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    // Das Test-PDF hat 3 Seiten -> die untere Leiste zeigt "Seite x / 3".
    expect(find.textContaining('/ 3'), findsOneWidget);
  });
}
