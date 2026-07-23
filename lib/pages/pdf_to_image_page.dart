import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:share_plus/share_plus.dart';

import '../file_naming.dart';
import '../license_service.dart';
import '../open_in_app.dart';
import '../usage_gate.dart';
import '../widgets/responsive_cards.dart';
import '../zoom_html.dart';

enum OutputFormat { png, jpeg, html }

/// Richtung, in der eine große Seite in Streifen zerschnitten wird.
/// [leftRight] = senkrechte Schnitte (Spalten, zum Durchwischen links→rechts),
/// [topBottom] = waagrechte Schnitte (Zeilen, oben→unten).
enum StripAxis { leftRight, topBottom }

/// Kodiert die von pdfium gelieferten BGRA-Rohpixel in einem Hintergrund-
/// Isolate zu PNG bzw. JPEG (hält die UI während großer Seiten flüssig).
/// Die Pixel kommen als [TransferableTypedData] – so wandern sie ohne zweite
/// Kopie in den Isolate (spart bei großen Seiten viel Speicher).
Uint8List _encodePage((int, int, TransferableTypedData, bool, int) e) {
  final (width, height, transferable, isPng, quality) = e;
  final image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: transferable.materialize(),
    order: img.ChannelOrder.bgra,
  );
  return isPng ? img.encodePng(image) : img.encodeJpg(image, quality: quality);
}

/// Renderplan für eine Seite: Zielgröße in Pixeln, effektiver DPI und – falls
/// aufgeteilt – Anzahl und Richtung der Streifen.
class _PagePlan {
  _PagePlan(this.pageNo, this.fullW, this.fullH, this.effDpi, this.strips,
      this.leftRight);
  final int pageNo;
  final double fullW;
  final double fullH;
  final int effDpi;
  final int strips;
  final bool leftRight;
}

/// Modus „PDF → Bild": wandelt PDF-Seiten in PNG/JPEG um.
class PdfToImagePage extends StatefulWidget {
  const PdfToImagePage({super.key, this.initialPdfPath});

  /// Optional vorausgewählte PDF (z. B. aus „Öffnen mit" oder dem Reader).
  final String? initialPdfPath;

  @override
  State<PdfToImagePage> createState() => PdfToImagePageState();
}

class PdfToImagePageState extends State<PdfToImagePage> {
  String? _pdfPath;
  int _pageCount = 0;

  int _dpi = 300;
  OutputFormat _format = OutputFormat.png;
  int _jpegQuality = 92;
  bool _splitStrips = false;
  StripAxis _stripAxis = StripAxis.leftRight;
  int _stripCount = 4;
  bool _allPages = true;
  final _pageRangeController = TextEditingController();
  String? _outputDir;
  final _fileNameController = TextEditingController();

  bool _busy = false;
  bool _dragging = false;
  bool _cancelRequested = false;
  // Wurde auf dem Handy mind. eine Seite wegen ihrer Größe herunterskaliert?
  // (Dann Hinweis auf die schärfere Windows-Desktop-App zeigen.)
  bool _largePageDownscaled = false;
  PdfPageRenderCancellationToken? _renderToken;
  double _progress = 0;
  String _statusText = '';
  final List<String> _resultFiles = [];

  final _dpiController = TextEditingController(text: '300');
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget.initialPdfPath != null) {
      _loadPdf(widget.initialPdfPath!);
    }
  }

  @override
  void dispose() {
    _pageRangeController.dispose();
    _dpiController.dispose();
    _fileNameController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Von außen (Öffnen-Knopf oben) eine PDF vorauswählen/laden.
  Future<void> openExternalPdf(String path) => _loadPdf(path);

  Future<void> _loadPdf(String path) async {
    int pages = 0;
    try {
      final doc = await PdfDocument.openFile(path);
      pages = doc.pages.length;
      await doc.dispose();
    } catch (e) {
      _showError('PDF konnte nicht geöffnet werden: $e');
      return;
    }
    if (!mounted) return;
    setState(() {
      _pdfPath = path;
      _pageCount = pages;
      _resultFiles.clear();
      _statusText = '';
      _outputDir ??= p.dirname(path);
      _fileNameController.text = p.basenameWithoutExtension(path);
    });
  }

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    final path = result?.files.single.path;
    if (path != null) await _loadPdf(path);
  }

  Future<void> _pickOutputDir() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir != null) setState(() => _outputDir = dir);
  }

  List<int> _parsePageRange(String input, int maxPage) {
    final Set<int> pages = {};
    for (final part in input.split(',')) {
      final token = part.trim();
      if (token.isEmpty) continue;
      if (token.contains('-')) {
        final bounds = token.split('-');
        if (bounds.length != 2) continue;
        final a = int.tryParse(bounds[0].trim());
        final b = int.tryParse(bounds[1].trim());
        if (a == null || b == null) continue;
        final lo = a < b ? a : b;
        final hi = a < b ? b : a;
        for (int i = lo; i <= hi; i++) {
          if (i >= 1 && i <= maxPage) pages.add(i);
        }
      } else {
        final n = int.tryParse(token);
        if (n != null && n >= 1 && n <= maxPage) pages.add(n);
      }
    }
    final list = pages.toList()..sort();
    return list;
  }

  /// Rendert einen (Teil-)Bereich einer Seite und kodiert ihn zu PNG/JPEG-Bytes.
  /// [fullW]/[fullH] = virtuelle Gesamtgröße der Seite in Pixeln (Vollauflösung).
  /// [x]/[y]/[w]/[h] = auszuschneidender Bereich darin; sind [w]/[h] null, wird
  /// die ganze Seite gerendert. Gibt null zurück bei Abbruch oder Fehler.
  Future<Uint8List?> _renderRegionToBytes(
    PdfPage page, {
    required double fullW,
    required double fullH,
    int x = 0,
    int y = 0,
    int? w,
    int? h,
    required bool isPng,
  }) async {
    final token = page.createCancellationToken();
    _renderToken = token;
    final rendered = await page.render(
      x: x,
      y: y,
      width: w,
      height: h,
      fullWidth: fullW,
      fullHeight: fullH,
      backgroundColor: 0xFFFFFFFF,
      cancellationToken: token,
    );
    _renderToken = null;
    if (rendered == null) return null;
    // Rohpixel (BGRA) in einen transferierbaren Puffer packen, das native Bild
    // sofort freigeben, dann im Hintergrund-Isolate kodieren.
    final params = (
      rendered.width,
      rendered.height,
      TransferableTypedData.fromList([rendered.pixels]),
      isPng,
      _jpegQuality,
    );
    rendered.dispose();
    return compute(_encodePage, params);
  }

  Future<void> _convert() async {
    if (_pdfPath == null) return;

    List<int> targetPages;
    if (_allPages) {
      targetPages = [for (int i = 1; i <= _pageCount; i++) i];
    } else {
      targetPages = _parsePageRange(_pageRangeController.text, _pageCount);
      if (targetPages.isEmpty) {
        _showError(
            'Keine gültigen Seiten. Beispiel: 1-3,5 (PDF hat $_pageCount Seiten).');
        return;
      }
    }

    // Gratis-Kontingent prüfen (Paywall, falls aufgebraucht).
    if (!mounted) return;
    if (!await ensureCanConvert(context)) return;

    final outDir = _outputDir ?? p.dirname(_pdfPath!);
    final customName = sanitizeFileName(_fileNameController.text);
    final baseName =
        customName.isEmpty ? p.basenameWithoutExtension(_pdfPath!) : customName;
    final isPng = _format == OutputFormat.png;
    final ext = isPng ? 'png' : 'jpg';
    final pad = _pageCount >= 100 ? 3 : 2;

    // Speicher-/Sicherheitsbudget für den Rohbild-Puffer (BGRA = 4 Byte/Pixel).
    // pdfium legt die Seite als EINEN zusammenhängenden Puffer an. Auf 32-bit-
    // Geräten (Handy) ist eine Uint8List max. 1073741823 Byte (≈ 1 GB) lang –
    // größer ⇒ „length must be in the range [0, 1073741823]". Auf dem Desktop
    // (64-bit) gibt es diese Grenze nicht, dort ist der RAM das Limit → deutlich
    // großzügiger, damit sehr große Seiten maximal scharf werden.
    final isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final int maxRasterBytes = isDesktop
        ? 1536 * 1024 * 1024 // ~1,5 GB  → bis ~19000×19000 px (viel RAM nötig)
        : 256 * 1024 * 1024; //  256 MB  → bis ~8000×8000 px (32-bit-Handy-Limit)

    setState(() {
      _busy = true;
      _cancelRequested = false;
      _largePageDownscaled = false;
      _progress = 0;
      _resultFiles.clear();
      _statusText = 'Wird vorbereitet …';
    });

    PdfDocument? doc;
    try {
      doc = await PdfDocument.openFile(_pdfPath!);

      if (_format == OutputFormat.html) {
        // Zoom-HTML: je Seite eine Datei mit Kachel-Pyramide (Karten-Zoom).
        // Kein Downscale nötig – gerendert wird streifenweise in voller DPI.
        for (int idx = 0;
            idx < targetPages.length && !_cancelRequested;
            idx++) {
          final pageNo = targetPages[idx];
          final page = doc.pages[pageNo - 1];
          final single = targetPages.length == 1;
          final fileName = single
              ? '$baseName.html'
              : '${baseName}_Seite_${pageNo.toString().padLeft(pad, '0')}.html';
          final outPath = p.join(outDir, fileName);
          final pageBase = idx / targetPages.length;
          final ok = await writeZoomHtml(
            page: page,
            outPath: outPath,
            title: single ? baseName : '$baseName – Seite $pageNo',
            dpi: _dpi.clamp(72, 600),
            stripBudgetBytes: maxRasterBytes ~/ 2,
            onToken: (t) => _renderToken = t,
            isCancelled: () => _cancelRequested,
            onProgress: (status, frac) {
              if (!mounted) return;
              setState(() {
                _statusText = single
                    ? status
                    : 'Seite $pageNo (${idx + 1}/${targetPages.length}): $status';
                _progress = pageBase + frac / targetPages.length;
              });
            },
          );
          if (ok) _resultFiles.add(outPath);
        }
      } else {

      // Vorab je Seite planen: Zielgröße (mit evtl. Downscale beim Einzelbild)
      // und Streifen-Anzahl. So kennt der Fortschrittsbalken die Gesamtarbeit.
      final plans = <_PagePlan>[];
      for (final pageNo in targetPages) {
        final page = doc.pages[pageNo - 1];
        double fullW = page.width * _dpi / 72.0;
        double fullH = page.height * _dpi / 72.0;
        int effDpi = _dpi;

        if (_splitStrips) {
          // Streifen: volle DPI behalten und in Streifen zerlegen. Anzahl bei
          // Bedarf erhöhen, damit jeder einzelne Streifen ins Budget passt.
          final leftRight = _stripAxis == StripAxis.leftRight;
          int n = _stripCount < 1 ? 1 : _stripCount;
          while (n < 100000) {
            final double stripBytes = leftRight
                ? (fullW / n) * fullH * 4
                : fullW * (fullH / n) * 4;
            if (stripBytes <= maxRasterBytes) break;
            n++;
          }
          plans.add(_PagePlan(pageNo, fullW, fullH, effDpi, n, leftRight));
        } else {
          // Einzelbild: zu große Seite gleichmäßig herunterskalieren.
          final double rasterBytes = fullW * fullH * 4;
          if (rasterBytes > maxRasterBytes) {
            final scale = math.sqrt(maxRasterBytes / rasterBytes);
            fullW *= scale;
            fullH *= scale;
            effDpi = (_dpi * scale).floor();
            if (!isDesktop) _largePageDownscaled = true;
          }
          if (fullW < 1) fullW = 1;
          if (fullH < 1) fullH = 1;
          plans.add(_PagePlan(pageNo, fullW, fullH, effDpi, 1, true));
        }
      }

      final int totalUnits = plans.fold(0, (sum, pl) => sum + pl.strips);
      int done = 0;

      for (final plan in plans) {
        if (_cancelRequested) break;
        final page = doc.pages[plan.pageNo - 1];
        final int fullWi = plan.fullW.floor().clamp(1, 1 << 30);
        final int fullHi = plan.fullH.floor().clamp(1, 1 << 30);
        final pageNoStr = plan.pageNo.toString().padLeft(pad, '0');

        if (plan.strips <= 1) {
          setState(() {
            _progress = totalUnits == 0 ? 0 : done / totalUnits;
            _statusText = plan.effDpi < _dpi
                ? 'Seite ${plan.pageNo} wird gerendert …\n'
                    'Sehr große Seite – auf ${plan.effDpi} dpi begrenzt (max. Auflösung).'
                : 'Seite ${plan.pageNo} wird gerendert …';
          });
          final bytes = await _renderRegionToBytes(page,
              fullW: fullWi.toDouble(), fullH: fullHi.toDouble(), isPng: isPng);
          if (bytes == null) {
            if (_cancelRequested) break;
            throw Exception(
                'Seite ${plan.pageNo} konnte nicht gerendert werden.');
          }
          final outPath = p.join(outDir, '${baseName}_Seite_$pageNoStr.$ext');
          await File(outPath).writeAsBytes(bytes);
          _resultFiles.add(outPath);
          done++;
          setState(() => _progress = totalUnits == 0 ? 1 : done / totalUnits);
        } else {
          final int n = plan.strips;
          final int stripPad = n >= 100 ? 3 : 2;
          for (int i = 0; i < n; i++) {
            if (_cancelRequested) break;
            int x, y, w, h;
            if (plan.leftRight) {
              final x0 = (i * fullWi / n).floor();
              final x1 = ((i + 1) * fullWi / n).floor();
              x = x0;
              y = 0;
              w = x1 - x0;
              h = fullHi;
            } else {
              final y0 = (i * fullHi / n).floor();
              final y1 = ((i + 1) * fullHi / n).floor();
              x = 0;
              y = y0;
              w = fullWi;
              h = y1 - y0;
            }
            if (w < 1) w = 1;
            if (h < 1) h = 1;
            setState(() {
              _progress = totalUnits == 0 ? 0 : done / totalUnits;
              _statusText =
                  'Seite ${plan.pageNo}: Streifen ${i + 1}/$n wird gerendert …';
            });
            final bytes = await _renderRegionToBytes(page,
                fullW: fullWi.toDouble(),
                fullH: fullHi.toDouble(),
                x: x,
                y: y,
                w: w,
                h: h,
                isPng: isPng);
            if (bytes == null) {
              if (_cancelRequested) break;
              throw Exception(
                  'Seite ${plan.pageNo}, Streifen ${i + 1} konnte nicht gerendert werden.');
            }
            final stripStr = (i + 1).toString().padLeft(stripPad, '0');
            final outPath = p.join(outDir,
                '${baseName}_Seite_${pageNoStr}_Streifen_$stripStr.$ext');
            await File(outPath).writeAsBytes(bytes);
            _resultFiles.add(outPath);
            done++;
            setState(() => _progress = totalUnits == 0 ? 1 : done / totalUnits);
          }
        }
      }
      }
      if (_cancelRequested) {
        setState(() => _statusText = _resultFiles.isEmpty
            ? 'Abgebrochen.'
            : 'Abgebrochen – ${_resultFiles.length} Bild(er) gespeichert in:\n$outDir');
      } else {
        await LicenseService.instance.registerConversion();
        var hint = '';
        if (_largePageDownscaled) {
          hint = '\n\nℹ️ Sehr große Seite(n) wurden zum Speichern verkleinert. '
              'Die Windows-Desktop-App von „PDF zu Bild" kann solche Seiten in '
              'deutlich höherer Auflösung (schärfer) umwandeln. Tipp: Das '
              'Format „Zoom (HTML)" zeigt auch riesige Seiten in voller '
              'Schärfe.';
        } else if (_format == OutputFormat.html && !isDesktop) {
          hint = '\n\nℹ️ Zum Ansehen die Datei in der Dateien-App antippen '
              '(öffnet im Browser) oder über „Teilen" weitergeben.';
        }
        setState(() => _statusText =
            '✓ Fertig: ${_resultFiles.length} Datei(en) in:\n$outDir$hint');
      }
    } catch (e) {
      _showError('Fehler beim Umwandeln: $e');
      setState(() => _statusText = 'Abgebrochen wegen Fehler.');
    } finally {
      _renderToken = null;
      await doc?.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareResults() async {
    if (_resultFiles.isEmpty) return;
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: _resultFiles.map((f) => XFile(f)).toList(),
        ),
      );
    } catch (e) {
      _showError('Teilen nicht möglich: $e');
    }
  }

  /// Öffnet die gerade erzeugten Dateien: Bilder in der App (blätterbar),
  /// Zoom-HTML im Standard-Browser (Desktop) bzw. mit Hinweis (Handy).
  Future<void> _openResult() async {
    if (_resultFiles.isEmpty) return;
    final first = _resultFiles.first;
    if (p.extension(first).toLowerCase() == '.html') {
      try {
        if (Platform.isWindows) {
          await Process.run('cmd', ['/c', 'start', '', first]);
          return;
        } else if (Platform.isLinux) {
          await Process.run('xdg-open', [first]);
          return;
        }
      } catch (_) {}
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Bitte die HTML-Datei in der Dateien-App antippen – '
            'sie öffnet dann im Browser.'),
        duration: Duration(seconds: 5),
      ));
      return;
    }
    await openPathsInApp(context, _resultFiles);
  }

  Future<void> _openOutputFolder() async {
    final dir = _outputDir;
    if (dir == null) return;
    try {
      if (Platform.isWindows) {
        await Process.run('explorer', [dir]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [dir]);
      }
    } catch (_) {}
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: Theme.of(context).colorScheme.error,
      duration: const Duration(seconds: 5),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final hasPdf = _pdfPath != null;
    final canShare = _resultFiles.isNotEmpty && !_busy;
    final isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;

    Widget body = Scrollbar(
      controller: _scrollController,
      thumbVisibility: isDesktop,
      child: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.all(20),
        children: [
        ResponsiveCards(
          enabled: isDesktop,
          children: [
        _Card(
          title: '1. PDF auswählen',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : _pickPdf,
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('PDF-Datei wählen'),
              ),
              if (isDesktop)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('… oder eine PDF hierher ziehen',
                      style: TextStyle(fontSize: 12)),
                ),
              if (hasPdf) ...[
                const SizedBox(height: 12),
                Text(p.basename(_pdfPath!),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('$_pageCount Seite(n)'),
              ],
            ],
          ),
        ),
        _Card(
          title: '2. Qualität (DPI)',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Slider(
                    value: _dpi.toDouble().clamp(72, 600),
                    min: 72,
                    max: 600,
                    divisions: (600 - 72) ~/ 6,
                    label: '$_dpi dpi',
                    onChanged: _busy
                        ? null
                        : (v) => setState(() {
                              _dpi = v.round();
                              _dpiController.text = '$_dpi';
                            }),
                  ),
                ),
                SizedBox(
                  width: 64,
                  child: TextField(
                    controller: _dpiController,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(isDense: true),
                    onSubmitted: (v) {
                      final n = int.tryParse(v.trim());
                      if (n != null) {
                        setState(() => _dpi = n.clamp(36, 1200));
                        _dpiController.text = '$_dpi';
                      }
                    },
                  ),
                ),
                const Padding(
                    padding: EdgeInsets.only(left: 4), child: Text('dpi')),
              ]),
              Wrap(
                spacing: 8,
                children: [150, 300, 400, 600]
                    .map((d) => ActionChip(
                          label: Text('$d'),
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                    _dpi = d;
                                    _dpiController.text = '$d';
                                  }),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 4),
              Text(
                _dpi >= 300
                    ? 'Sehr scharf – gut für Text und zum Ausdrucken.'
                    : 'Für Bildschirm okay, Text wirkt evtl. weicher.',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.outline),
              ),
            ],
          ),
        ),
        _Card(
          title: '3. Bildformat',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<OutputFormat>(
                segments: const [
                  ButtonSegment(
                      value: OutputFormat.png,
                      label: Text('PNG'),
                      icon: Icon(Icons.image)),
                  ButtonSegment(
                      value: OutputFormat.jpeg,
                      label: Text('JPEG'),
                      icon: Icon(Icons.photo)),
                  ButtonSegment(
                      value: OutputFormat.html,
                      label: Text('Zoom'),
                      icon: Icon(Icons.travel_explore)),
                ],
                selected: {_format},
                onSelectionChanged: _busy
                    ? null
                    : (s) => setState(() => _format = s.first),
              ),
              const SizedBox(height: 8),
              Text(
                switch (_format) {
                  OutputFormat.png =>
                    'PNG: verlustfrei, beste Schärfe, größere Dateien.',
                  OutputFormat.jpeg =>
                    'JPEG: kleinere Dateien, bei Text leichte Artefakte.',
                  OutputFormat.html =>
                    'Zoom (HTML): eine Datei mit Karten-Zoom – ideal für '
                        'riesige Seiten (Poster, Zeitleisten). Öffnet im '
                        'Browser, zoomt sofort scharf ohne Wartezeit.',
                },
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.outline),
              ),
              if (_format == OutputFormat.jpeg) ...[
                const SizedBox(height: 8),
                Row(children: [
                  const Text('Qualität '),
                  Expanded(
                    child: Slider(
                      value: _jpegQuality.toDouble(),
                      min: 50,
                      max: 100,
                      divisions: 50,
                      label: '$_jpegQuality',
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _jpegQuality = v.round()),
                    ),
                  ),
                  Text('$_jpegQuality'),
                ]),
              ],
            ],
          ),
        ),
        _Card(
          title: '4. Seiten',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RadioGroup<bool>(
                groupValue: _allPages,
                onChanged: (v) {
                  if (_busy) return;
                  setState(() => _allPages = v ?? true);
                },
                child: const Column(children: [
                  RadioListTile<bool>(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Alle Seiten'),
                    value: true,
                  ),
                  RadioListTile<bool>(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Bestimmte Seiten'),
                    value: false,
                  ),
                ]),
              ),
              if (!_allPages)
                Padding(
                  padding: const EdgeInsets.only(left: 12, top: 4),
                  child: TextField(
                    controller: _pageRangeController,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      hintText: 'z. B. 1-3,5,8',
                      labelText: 'Seiten',
                      isDense: true,
                    ),
                  ),
                ),
            ],
          ),
        ),
        _Card(
          title: '5. Zielordner & Name',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _pickOutputDir,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Ordner wählen'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _fileNameController,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _outputDir ?? 'Standard: gleicher Ordner wie das PDF',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.outline),
              ),
            ],
          ),
        ),
        // Streifen-Aufteilung betrifft nur Bild-Ausgaben; die Zoom-HTML
        // zeigt riesige Seiten ohnehin in voller Schärfe.
        if (_format != OutputFormat.html)
        _Card(
          title: '6. Große Seite aufteilen',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('In Streifen aufteilen'),
                subtitle: const Text(
                    'Erzeugt mehrere scharfe Teilbilder statt eines Riesenbilds '
                    '– am Handy flüssig durchwischbar.'),
                value: _splitStrips,
                onChanged:
                    _busy ? null : (v) => setState(() => _splitStrips = v),
              ),
              if (_splitStrips) ...[
                const SizedBox(height: 8),
                const Text('Richtung'),
                const SizedBox(height: 4),
                SegmentedButton<StripAxis>(
                  segments: const [
                    ButtonSegment(
                        value: StripAxis.leftRight,
                        label: Text('Links → rechts'),
                        icon: Icon(Icons.swap_horiz)),
                    ButtonSegment(
                        value: StripAxis.topBottom,
                        label: Text('Oben → unten'),
                        icon: Icon(Icons.swap_vert)),
                  ],
                  selected: {_stripAxis},
                  onSelectionChanged: _busy
                      ? null
                      : (s) => setState(() => _stripAxis = s.first),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  const Text('Streifen '),
                  Expanded(
                    child: Slider(
                      value: _stripCount.toDouble().clamp(2, 20),
                      min: 2,
                      max: 20,
                      divisions: 18,
                      label: '$_stripCount',
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _stripCount = v.round()),
                    ),
                  ),
                  SizedBox(width: 28, child: Text('$_stripCount')),
                ]),
                Text(
                  'Bei sehr großen Seiten wird die Anzahl automatisch erhöht, '
                  'damit jeder Streifen sicher passt. Mehr Streifen = flüssiger '
                  'am Handy.',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.outline),
                ),
              ],
            ],
          ),
        ),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: (hasPdf && !_busy) ? _convert : null,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.auto_awesome),
          label: Text(_busy ? 'Wird umgewandelt …' : 'Umwandeln'),
        ),
        const RemainingFreeBadge(),
        if (_busy) ...[
          const SizedBox(height: 12),
          // Vor der ersten fertigen Seite ist der Fortschritt noch 0 → laufender
          // (indeterminater) Balken, damit große Einzelseiten nicht „eingefroren"
          // wirken; danach füllt er sich pro Seite.
          LinearProgressIndicator(value: _progress == 0 ? null : _progress),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _cancelRequested
                  ? null
                  : () {
                      setState(() => _cancelRequested = true);
                      _renderToken?.cancel();
                    },
              icon: const Icon(Icons.close),
              label:
                  Text(_cancelRequested ? 'Wird abgebrochen …' : 'Abbrechen'),
            ),
          ),
        ],
        if (_statusText.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(_statusText),
          ),
        ],
        if (canShare) ...[
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: _shareResults,
                icon: const Icon(Icons.share),
                label: const Text('Teilen / WhatsApp'),
              ),
            ),
            const SizedBox(width: 12),
            // Öffnet die erzeugten Bilder (blätterbar bei mehreren Seiten).
            OutlinedButton.icon(
              onPressed: _openResult,
              icon: const Icon(Icons.open_in_new),
              label: const Text('Öffnen'),
            ),
          ]),
          if (isDesktop) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _openOutputFolder,
              icon: const Icon(Icons.folder),
              label: const Text('Ordner öffnen'),
            ),
          ],
        ],
      ],
      ),
    );

    body = Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isDesktop ? 1000 : 640),
        child: body,
      ),
    );

    if (!isDesktop) return body;

    // Drag & Drop nur auf dem Desktop.
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (detail) async {
        setState(() => _dragging = false);
        final pdf = detail.files
            .map((f) => f.path)
            .firstWhere((path) => path.toLowerCase().endsWith('.pdf'),
                orElse: () => '');
        if (pdf.isNotEmpty) {
          await _loadPdf(pdf);
        } else {
          _showError('Bitte eine PDF-Datei ziehen.');
        }
      },
      child: Stack(
        children: [
          body,
          if (_dragging)
            Positioned.fill(
              child: Container(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.12),
                child: Center(
                  child: Text('PDF hier ablegen',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
