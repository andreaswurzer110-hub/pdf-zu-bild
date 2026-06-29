import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pdfx/pdfx.dart';

/// Reader-Modus: zeigt eine geöffnete PDF mit Zoom und Seitenanzeige.
class PdfReaderPage extends StatefulWidget {
  const PdfReaderPage({super.key, required this.path});
  final String path;

  @override
  State<PdfReaderPage> createState() => _PdfReaderPageState();
}

class _PdfReaderPageState extends State<PdfReaderPage> {
  late final PdfControllerPinch _controller;
  int _page = 1;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _controller = PdfControllerPinch(
      document: PdfDocument.openFile(widget.path),
    );
  }

  @override
  void didUpdateWidget(PdfReaderPage old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      _controller.loadDocument(PdfDocument.openFile(widget.path));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        PdfViewPinch(
          controller: _controller,
          onDocumentLoaded: (doc) => setState(() => _total = doc.pagesCount),
          onPageChanged: (page) => setState(() => _page = page),
        ),
        // Dateiname + Seitenanzeige unten.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            color: scheme.surface.withValues(alpha: 0.85),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    p.basename(widget.path),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(_total > 0 ? 'Seite $_page / $_total' : '…'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
