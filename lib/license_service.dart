import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Verwaltet die Gratis-Umwandlungen und den Vollversion-Status.
/// Modell: die ersten [freeLimit] Umwandlungen sind gratis, danach Paywall.
/// Linux ist komplett kostenlos (immer Vollversion).
class LicenseService extends ChangeNotifier {
  LicenseService._();
  static final LicenseService instance = LicenseService._();

  static const int freeLimit = 5;
  static const String _kCount = 'conversion_count';
  static const String _kPro = 'is_pro';

  int _count = 0;
  bool _proStored = false;
  bool _loaded = false;

  /// Auf Linux gibt es keine Store-Bezahlung → dort alles freigeschaltet.
  bool get _linuxFree => Platform.isLinux;

  bool get isPro => _proStored || _linuxFree;
  int get used => _count;
  int get remainingFree => (freeLimit - _count).clamp(0, freeLimit);

  /// true, wenn das Gratis-Kontingent aufgebraucht und nicht freigeschaltet ist.
  bool get isLocked => !isPro && _count >= freeLimit;

  Future<void> init() async {
    if (_loaded) return;
    final sp = await SharedPreferences.getInstance();
    _count = sp.getInt(_kCount) ?? 0;
    _proStored = sp.getBool(_kPro) ?? false;
    _loaded = true;
    notifyListeners();
  }

  /// Eine erfolgreiche Umwandlung zählen (zählt nur in der Gratis-Phase).
  Future<void> registerConversion() async {
    if (isPro) return;
    _count++;
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_kCount, _count);
    notifyListeners();
  }

  /// Vollversion freischalten (nach erfolgreichem Kauf).
  Future<void> unlockPro() async {
    _proStored = true;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kPro, true);
    notifyListeners();
  }

  /// Nur für Tests/Support: Zähler zurücksetzen.
  Future<void> resetForTesting() async {
    final sp = await SharedPreferences.getInstance();
    _count = 0;
    _proStored = false;
    await sp.remove(_kCount);
    await sp.remove(_kPro);
    notifyListeners();
  }
}
