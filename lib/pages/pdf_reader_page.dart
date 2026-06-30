import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:pdfx/pdfx.dart';

/// Reader-Modus: zeigt eine geöffnete PDF mit Seitenanzeige.
/// Auf Handy/Tablet mit Pinch-Zoom (PdfViewPinch), auf Desktop mit PdfView
/// (PdfViewPinch wird unter Windows/Linux nicht unterstützt). Damit am Desktop
/// trotzdem gezoomt werden kann, liegt dort ein InteractiveViewer darüber:
/// Strg+Mausrad oder die +/–-Knöpfe zoomen, Ziehen verschiebt.
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
  // Throttle fürs Mausrad (sonst blättert ein Scroll mehrere Seiten weiter).
  DateTime _lastWheel = DateTime.fromMillisecondsSinceEpoch(0);
  // Zoom am Desktop.
  final _tc = TransformationController();
  Size? _viewport;

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
    _tc.dispose();
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

  void _resetZoom() => _tc.value = _tc.value.clone()..setIdentity();

  /// Zoomt um einen Fokuspunkt (Szenen-Koordinaten), begrenzt auf 1×…5×.
  void _zoomBy(double factor, Offset focalScene) {
    final current = _tc.value.getMaxScaleOnAxis();
    final target = (current * factor).clamp(1.0, 5.0);
    final f = target / current;
    if ((f - 1.0).abs() < 0.001) return;
    _tc.value = _tc.value.clone()
      ..translateByDouble(focalScene.dx, focalScene.dy, 0, 1)
      ..scaleByDouble(f, f, f, 1)
      ..translateByDouble(-focalScene.dx, -focalScene.dy, 0, 1);
  }

  /// Zoom über die +/–-Knöpfe: um die Bildschirmmitte.
  void _zoomCentered(double factor) {
    final size = _viewport;
    if (size == null) return;
    _zoomBy(factor, _tc.toScene(Offset(size.width / 2, size.height / 2)));
  }

  /// Mausrad am Desktop: Strg+Rad = Zoom, sonst vorige/nächste Seite.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (HardwareKeyboard.instance.isControlPressed) {
      final factor = event.scrollDelta.dy < 0 ? 1.2 : 1 / 1.2;
      _zoomBy(factor, _tc.toScene(event.localPosition));
      return;
    }
    final now = DateTime.now();
    if (now.difference(_lastWheel).inMilliseconds < 220) return;
    _lastWheel = now;
    if (event.scrollDelta.dy > 0) {
      if (_page < _total) _next();
    } else if (event.scrollDelta.dy < 0) {
      if (_page > 1) _prev();
    }
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
        : LayoutBuilder(
            builder: (context, constraints) {
              _viewport = Size(constraints.maxWidth, constraints.maxHeight);
              return Listener(
                onPointerSignal: _onPointerSignal,
                child: InteractiveViewer(
                  transformationController: _tc,
                  minScale: 1,
                  maxScale: 5,
                  child: PdfView(
                    controller: _ctrl!,
                    scrollDirection: Axis.vertical,
                    onDocumentLoaded: (doc) =>
                        setState(() => _total = doc.pagesCount),
                    // Beim Seitenwechsel Zoom zurücksetzen.
                    onPageChanged: (page) => setState(() {
                      _page = page;
                      _resetZoom();
                    }),
                  ),
                ),
              );
            },
          );

    return Stack(
      children: [
        Positioned.fill(child: ColoredBox(color: scheme.surfaceContainerHighest)),
        Positioned.fill(child: viewer),
        // Untere Leiste: Dateiname, Zoom (Desktop), Blättern, Seitenanzeige.
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
                if (!_pinch) ...[
                  IconButton(
                    tooltip: 'Verkleinern',
                    icon: const Icon(Icons.zoom_out),
                    onPressed: () => _zoomCentered(1 / 1.25),
                  ),
                  IconButton(
                    tooltip: 'Vergrößern',
                    icon: const Icon(Icons.zoom_in),
                    onPressed: () => _zoomCentered(1.25),
                  ),
                ],
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
