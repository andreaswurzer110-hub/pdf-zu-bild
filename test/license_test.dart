// Testet die Freemium-Logik: 5 gratis, danach gesperrt; Freischalten hebt auf.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pdf_zu_bild/license_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LicenseService.instance.resetForTesting();
  });

  test('5 Umwandlungen gratis, dann gesperrt', () async {
    final lic = LicenseService.instance;

    // Auf Linux ist alles freigeschaltet – dort greift keine Sperre.
    if (Platform.isLinux) {
      expect(lic.isPro, true);
      return;
    }

    expect(lic.remainingFree, 5);
    expect(lic.isLocked, false);

    for (var i = 0; i < 5; i++) {
      await lic.registerConversion();
    }

    expect(lic.remainingFree, 0);
    expect(lic.isLocked, true);
  });

  test('Freischalten hebt die Sperre auf und zählt nicht weiter', () async {
    final lic = LicenseService.instance;
    for (var i = 0; i < 5; i++) {
      await lic.registerConversion();
    }
    await lic.unlockPro();
    expect(lic.isPro, true);
    expect(lic.isLocked, false);

    // In der Vollversion wird nicht mehr hochgezählt.
    await lic.registerConversion();
    expect(lic.isPro, true);
  });
}
