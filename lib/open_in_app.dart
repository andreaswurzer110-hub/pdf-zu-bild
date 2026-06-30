import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'pages/image_viewer_page.dart';
import 'pages/pdf_reader_page.dart';

/// Öffnet eine Datei in der App: PDF → Reader-Seite, Bild → Bildanzeige.
/// Wird als eigene Route geöffnet (mit Zurück-Pfeil), damit man danach
/// wieder zur Umwandlung kommt.
Future<void> openPathInApp(BuildContext context, String path) =>
    openPathsInApp(context, [path]);

/// Wie [openPathInApp], aber für mehrere Bilder (z. B. alle Seiten einer
/// umgewandelten PDF) — die Bildanzeige erlaubt dann das Blättern.
Future<void> openPathsInApp(
  BuildContext context,
  List<String> paths, {
  int initialIndex = 0,
}) async {
  if (paths.isEmpty) return;
  final isPdf = p.extension(paths[initialIndex]).toLowerCase() == '.pdf';
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => isPdf
          ? _ReaderScaffold(path: paths[initialIndex])
          : ImageViewerPage(paths: paths, initialIndex: initialIndex),
    ),
  );
}

/// Reader-Seite als eigenständige Route (eigener Scaffold mit Titel/Zurück).
class _ReaderScaffold extends StatelessWidget {
  const _ReaderScaffold({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        title: Text(p.basename(path), overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(child: PdfReaderPage(path: path)),
    );
  }
}
