import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// Einfache Bildanzeige mit Zoom/Verschieben (für den „Öffnen"-Button).
class ImageViewerPage extends StatelessWidget {
  const ImageViewerPage({super.key, required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        title: Text(p.basename(path), overflow: TextOverflow.ellipsis),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 6,
          child: Image.file(
            File(path),
            errorBuilder: (_, _, _) => const Text(
              'Bild konnte nicht geladen werden.',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
