// Einfacher Smoke-Test: Startet die App und prüft die Grundoberfläche.

import 'package:flutter_test/flutter_test.dart';

import 'package:pdf_zu_bild/main.dart';

void main() {
  testWidgets('App startet mit Umschalter und PDF→Bild-Modus', (tester) async {
    await tester.pumpWidget(const PdfZuBildApp());
    await tester.pump();

    // Umschalter „PDF ⇄ Bild" im Titel.
    expect(find.text('PDF'), findsWidgets);
    expect(find.text('Bild'), findsWidgets);

    // Start-Modus PDF→Bild zeigt oben den Datei-Button und die erste Karte.
    expect(find.text('PDF-Datei wählen'), findsOneWidget);
    expect(find.text('1. PDF auswählen'), findsOneWidget);
  });
}
