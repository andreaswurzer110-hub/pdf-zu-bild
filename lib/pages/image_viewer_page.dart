import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

/// Bildanzeige mit Zoom/Verschieben (für den „Öffnen"-Button). Bei mehreren
/// Pfaden (z. B. alle Seiten einer umgewandelten PDF) kann zwischen den
/// Bildern geblättert werden.
///
/// Nutzt [PhotoViewGallery] statt eines eigenen `PageView`+`InteractiveViewer`:
/// Beide Gesten (Wischen zum Blättern, Pinch zum Zoomen) konkurrieren sonst um
/// dieselben Pointer-Events, was auf Android dazu führte, dass Zoomen entweder
/// gar nicht reagierte oder stattdessen die nächste Seite aufgerufen wurde.
///
/// Auf dem Desktop gibt es kein Pinch und photo_view kann kein Mausrad-Zoom –
/// deshalb zusätzlich +/–-Knöpfe (alle Plattformen) und Mausrad-Zoom (Desktop),
/// die den [PhotoViewController] der aktuellen Seite skalieren.
class ImageViewerPage extends StatefulWidget {
  const ImageViewerPage({
    super.key,
    required this.paths,
    this.initialIndex = 0,
  });

  final List<String> paths;
  final int initialIndex;

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  late int _index;
  late final PageController _pageController;
  final _controllers = <int, PhotoViewController>{};

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.paths.length - 1);
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  PhotoViewController _controllerFor(int i) =>
      _controllers.putIfAbsent(i, () => PhotoViewController());

  void _go(int delta) {
    final next = (_index + delta).clamp(0, widget.paths.length - 1);
    _pageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
    );
  }

  /// Skaliert die aktuell sichtbare Seite um [factor] (begrenzt).
  void _zoom(double factor) {
    final c = _controllers[_index];
    if (c == null) return;
    final current = c.scale ?? 1.0;
    c.scale = (current * factor).clamp(0.1, 20.0);
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      _zoom(event.scrollDelta.dy < 0 ? 1.15 : 1 / 1.15);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final multi = widget.paths.length > 1;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        title: Text(
          multi
              ? '${p.basename(widget.paths[_index])}  (${_index + 1}/${widget.paths.length})'
              : p.basename(widget.paths[_index]),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Verkleinern',
            icon: const Icon(Icons.zoom_out),
            onPressed: () => _zoom(1 / 1.25),
          ),
          IconButton(
            tooltip: 'Vergrößern',
            icon: const Icon(Icons.zoom_in),
            onPressed: () => _zoom(1.25),
          ),
          if (multi) ...[
            IconButton(
              tooltip: 'Vorherige Seite',
              icon: const Icon(Icons.chevron_left),
              onPressed: _index > 0 ? () => _go(-1) : null,
            ),
            IconButton(
              tooltip: 'Nächste Seite',
              icon: const Icon(Icons.chevron_right),
              onPressed:
                  _index < widget.paths.length - 1 ? () => _go(1) : null,
            ),
          ],
        ],
      ),
      body: Listener(
        // Mausrad zoomt auf dem Desktop (vertikales Rad = dy; die horizontale
        // PageView reagiert nur auf dx, daher kein Konflikt mit dem Blättern).
        onPointerSignal: _isDesktop ? _onPointerSignal : null,
        child: PhotoViewGallery.builder(
          pageController: _pageController,
          itemCount: widget.paths.length,
          onPageChanged: (i) => setState(() => _index = i),
          backgroundDecoration: const BoxDecoration(color: Colors.black),
          builder: (context, i) => PhotoViewGalleryPageOptions(
            imageProvider: FileImage(File(widget.paths[i])),
            controller: _controllerFor(i),
            minScale: PhotoViewComputedScale.contained * 0.8,
            maxScale: PhotoViewComputedScale.covered * 4,
            initialScale: PhotoViewComputedScale.contained,
            errorBuilder: (context, error, stackTrace) => const Center(
              child: Text(
                'Bild konnte nicht geladen werden.',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
