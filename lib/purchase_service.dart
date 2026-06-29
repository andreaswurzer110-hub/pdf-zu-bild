import 'dart:async';
import 'dart:io';

import 'package:in_app_purchase/in_app_purchase.dart';

import 'license_service.dart';

/// Kapselt den In-App-Kauf der Vollversion.
/// Aktuell über `in_app_purchase` (Google Play / App Store). Auf Windows ist
/// die Store-Anbindung noch offen (Platzhalter), Linux ist gratis.
class PurchaseService {
  PurchaseService._();
  static final PurchaseService instance = PurchaseService._();

  /// Produkt-ID, die im Play Store / App Store angelegt werden muss.
  static const String productId = 'pdfzubild_full';
  static const String fallbackPrice = '2,99 €';

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  ProductDetails? _product;
  bool _storeReady = false;

  /// Plattformen, auf denen `in_app_purchase` Käufe unterstützt.
  bool get supported => Platform.isAndroid || Platform.isIOS;

  /// Anzuzeigender Preis (vom Store, sonst Fallback).
  String get displayPrice => _product?.price ?? fallbackPrice;

  /// Ist der Kauf gerade tatsächlich auslösbar?
  bool get canBuy => supported && _storeReady && _product != null;

  Future<void> init() async {
    if (!supported) return;
    try {
      _sub = _iap.purchaseStream.listen(_onUpdates, onError: (_) {});
      _storeReady = await _iap.isAvailable();
      if (_storeReady) {
        final resp = await _iap.queryProductDetails({productId});
        if (resp.productDetails.isNotEmpty) {
          _product = resp.productDetails.first;
        }
      }
    } catch (_) {
      _storeReady = false;
    }
  }

  Future<void> _onUpdates(List<PurchaseDetails> purchases) async {
    for (final pur in purchases) {
      if (pur.status == PurchaseStatus.purchased ||
          pur.status == PurchaseStatus.restored) {
        await LicenseService.instance.unlockPro();
      }
      if (pur.pendingCompletePurchase) {
        await _iap.completePurchase(pur);
      }
    }
  }

  /// Startet den Kauf. Rückgabe: null = ok (Ergebnis kommt per Stream),
  /// sonst eine Meldung, warum es (noch) nicht geht.
  Future<String?> buy() async {
    if (Platform.isLinux) return null; // dort gratis – sollte nicht vorkommen
    if (Platform.isWindows) {
      return 'Der Kauf läuft über den Microsoft Store, sobald die App dort '
          'veröffentlicht ist.';
    }
    if (!supported) return 'Auf dieser Plattform nicht verfügbar.';
    if (!_storeReady) return 'Store nicht verfügbar. Bist du angemeldet?';
    if (_product == null) {
      return 'Das Produkt ist im Store noch nicht eingerichtet.';
    }
    try {
      await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: _product!),
      );
      return null;
    } catch (e) {
      return 'Kauf konnte nicht gestartet werden: $e';
    }
  }

  Future<void> restore() async {
    if (supported) await _iap.restorePurchases();
  }

  void dispose() => _sub?.cancel();
}
