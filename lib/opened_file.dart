import 'dart:io';

import 'package:flutter/services.dart';

/// Ermittelt eine per „Öffnen mit" übergebene PDF-Datei.
/// - Windows/Linux: aus den Kommandozeilen-Argumenten.
/// - Android: über den MethodChannel aus der MainActivity.
class OpenedFile {
  static const _channel = MethodChannel('at.aw.pdfzubild/open');

  /// Sucht in den Programm-Argumenten (Desktop) nach einer PDF.
  static String? fromArgs(List<String> args) {
    for (final a in args) {
      if (a.toLowerCase().endsWith('.pdf') && File(a).existsSync()) {
        return a;
      }
    }
    return null;
  }

  /// Fragt Android nach einer per Intent geöffneten PDF.
  static Future<String?> fromAndroid() async {
    if (!Platform.isAndroid) return null;
    try {
      final path = await _channel.invokeMethod<String>('getOpenedFile');
      if (path != null && File(path).existsSync()) return path;
    } catch (_) {}
    return null;
  }
}
