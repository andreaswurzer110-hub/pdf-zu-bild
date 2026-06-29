import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pdfx/pdfx.dart';

/// Reader-Modus: zeigt eine geöffnete PDF mit Seitenanzeige.
/// Auf Handy/Tablet mit Pinch-Zoom (PdfViewPinch), auf Desktop mit PdfView
/// (PdfViewPinch wird unter Windows/Linux nicht unterstützt).
class PdfReaderPage extends StatefulWidget {
  const PdfReaderPage({super.key, required this.path});
  final String path;

  @override
  State<PdfReaderPage> createState() => _PdfReaderPageState();
}

class _PdfReaderPageState extends State<PdfReaderPage> {
  // Pinch nur auf mobilen Plattformen.
  bool get _pinch => Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  PdfController? _ctrl;
  PdfControllerPinch? _ctrlPinch;
  int _page = 1;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    final doc = PdfDocument.openFile(widget.path);
    if (_pinch) {
      _ctrlPinch = PdfControllerPinch(document: doc);
    } else {
      _ctrl = PdfController(document: doc);
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    _ctrlPinch?.dispose();
    super.dispose();
  }

  void _prev() {
    _ctrl?.previousPage(
        duration: const Duration(milliseconds: 250), curve: Curves.ease);
    _ctrlPinch?.previousPage(
        duration: const Duration(milliseconds: 250), curve: Curves.ease);
  }

  void _next() {
    _ctrl?.nextPage(
        duration: const Duration(milliseconds: 250), curve: Curves.ease);
    _ctrlPinch?.nextPage(
        duration: const Duration(milliseconds: 250), curve: Curves.ease);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final Widget viewer = _pinch
        ? PdfViewPinch(
            controller: _ctrlPinch!,
            onDocumentLoaded: (doc) =>
                setState(() => _total = doc.pagesCount),
            onPageChanged: (page) => setState(() => _page = page),
          )
        : PdfView(
            controller: _ctrl!,
            scrollDirection: Axis.vertical,
            onDocumentLoaded: (doc) =>
                setState(() => _total = doc.pagesCount),
            onPageChanged: (page) => setState(() => _page = page),
          );

    return Stack(
      children: [
        Positioned.fill(child: ColoredBox(color: scheme.surfaceContainerHighest)),
        Positioned.fill(child: viewer),
        // Untere Leiste: Dateiname, Blättern, Seitenanzeige.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
            color: scheme.surface.withValues(alpha: 0.9),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    p.basename(widget.path),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: 'Vorige Seite',
                  icon: const Icon(Icons.keyboard_arrow_up),
                  onPressed: _page > 1 ? _prev : null,
                ),
                Text(_total > 0 ? '$_page / $_total' : '…'),
                IconButton(
                  tooltip: 'Nächste Seite',
                  icon: const Icon(Icons.keyboard_arrow_down),
                  onPressed: _page < _total ? _next : null,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
