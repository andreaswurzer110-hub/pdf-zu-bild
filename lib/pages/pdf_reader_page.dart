import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

/// Reader-Modus: zeigt eine geöffnete PDF mit Seitenanzeige.
///
/// Nutzt `pdfrx` (pdfium) auf allen Plattformen inkl. Linux. Der `PdfViewer`
/// bringt Pinch-Zoom, Ziehen, Scrollen und Mausrad selbst mit – daher keine
/// eigene Zoom-/Wisch-Logik mehr. Die untere Leiste zeigt Dateiname, Zoom-
/// Knöpfe, Blättern und die Seitenanzeige.
class PdfReaderPage extends StatefulWidget {
  const PdfReaderPage({super.key, required this.path});
  final String path;

  @override
  State<PdfReaderPage> createState() => _PdfReaderPageState();
}

class _PdfReaderPageState extends State<PdfReaderPage> {
  final _controller = PdfViewerController();
  int _page = 1;
  int _total = 0;

  void _prev() {
    if (_controller.isReady && _page > 1) {
      _controller.goToPage(pageNumber: _page - 1);
    }
  }

  void _next() {
    if (_controller.isReady && _page < _total) {
      _controller.goToPage(pageNumber: _page + 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        Positioned.fill(
          child: PdfViewer.file(
            widget.path,
            controller: _controller,
            params: PdfViewerParams(
              backgroundColor: scheme.surfaceContainerHighest,
              onViewerReady: (doc, controller) =>
                  setState(() => _total = doc.pages.length),
              onPageChanged: (pageNumber) =>
                  setState(() => _page = pageNumber ?? _page),
            ),
          ),
        ),
        // Untere Leiste: Dateiname, Zoom, Blättern, Seitenanzeige.
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
                  tooltip: 'Verkleinern',
                  icon: const Icon(Icons.zoom_out),
                  onPressed: () {
                    if (_controller.isReady) _controller.zoomDown();
                  },
                ),
                IconButton(
                  tooltip: 'Vergrößern',
                  icon: const Icon(Icons.zoom_in),
                  onPressed: () {
                    if (_controller.isReady) _controller.zoomUp();
                  },
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
