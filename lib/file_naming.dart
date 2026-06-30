/// Macht einen vom Nutzer eingegebenen Dateinamen sicher für die
/// Verwendung als tatsächlicher Dateiname (keine Pfadtrenner/Sonderzeichen,
/// die unter Windows oder beim Zusammenbauen des Pfads stören).
String sanitizeFileName(String name) {
  final cleaned = name.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  return cleaned.isEmpty ? '' : cleaned;
}
