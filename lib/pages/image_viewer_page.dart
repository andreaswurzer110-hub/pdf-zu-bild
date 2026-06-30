import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// Bildanzeige mit Zoom/Verschieben (für den „Öffnen"-Button). Bei mehreren
/// Pfaden (z. B. alle Seiten einer umgewandelten PDF) kann zwischen den
/// Bildern geblättert werden.
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
  late final PageController _controller;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.paths.length - 1);
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final next = (_index + delta).clamp(0, widget.paths.length - 1);
    _controller.animateToPage(
      next,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
    );
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
        actions: multi
            ? [
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
              ]
            : null,
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.paths.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) => Center(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 6,
            child: Image.file(
              File(widget.paths[i]),
              errorBuilder: (_, _, _) => const Text(
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
