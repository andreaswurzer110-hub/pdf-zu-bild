// Einfacher Smoke-Test: Startet die App und prüft, dass die Oberfläche lädt.

import 'package:flutter_test/flutter_test.dart';

import 'package:pdf_zu_bild/main.dart';

void main() {
  testWidgets('App startet und zeigt die Hauptelemente', (tester) async {
    await tester.pumpWidget(const PdfZuBildApp());

    expect(find.text('PDF zu Bild'), findsOneWidget);
    expect(find.text('PDF-Datei wählen'), findsOneWidget);
    expect(find.text('Umwandeln'), findsOneWidget);
  });
}
