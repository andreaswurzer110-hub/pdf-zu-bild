import 'dart:io';

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

enum OutputFormat { png, jpeg }

/// Kodiert die von pdfium gelieferten BGRA-Rohpixel in einem Hintergrund-
/// Isolate zu PNG bzw. JPEG (hält die UI während großer Seiten flüssig).
Uint8List _encodePage((int, int, Uint8List, bool, int) e) {
  final (width, height, pixels, isPng, quality) = e;
  final image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: pixels.buffer,
    order: img.ChannelOrder.bgra,
  );
  return isPng ? img.encodePng(image) : img.encodeJpg(image, quality: quality);
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
  bool _allPages = true;
  final _pageRangeController = TextEditingController();
  String? _outputDir;
  final _fileNameController = TextEditingController();

  bool _busy = false;
  bool _dragging = false;
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

    setState(() {
      _busy = true;
      _progress = 0;
      _resultFiles.clear();
      _statusText = 'Wird vorbereitet …';
    });

    PdfDocument? doc;
    try {
      doc = await PdfDocument.openFile(_pdfPath!);
      for (int idx = 0; idx < targetPages.length; idx++) {
        final pageNo = targetPages[idx];
        setState(() => _statusText =
            'Seite $pageNo … (${idx + 1}/${targetPages.length})');

        final page = doc.pages[pageNo - 1];
        final rendered = await page.render(
          fullWidth: page.width * _dpi / 72.0,
          fullHeight: page.height * _dpi / 72.0,
          backgroundColor: 0xFFFFFFFF,
        );
        if (rendered == null) {
          throw Exception('Seite $pageNo konnte nicht gerendert werden.');
        }
        // Rohpixel (BGRA) kopieren, natives Bild sofort freigeben, dann im
        // Hintergrund-Isolate zu PNG/JPEG kodieren.
        final params = (
          rendered.width,
          rendered.height,
          Uint8List.fromList(rendered.pixels),
          isPng,
          _jpegQuality,
        );
        rendered.dispose();
        final bytes = await compute(_encodePage, params);

        final fileName =
            '${baseName}_Seite_${pageNo.toString().padLeft(pad, '0')}.$ext';
        final outPath = p.join(outDir, fileName);
        await File(outPath).writeAsBytes(bytes);
        _resultFiles.add(outPath);
        setState(() => _progress = (idx + 1) / targetPages.length);
      }
      await LicenseService.instance.registerConversion();
      setState(() => _statusText =
          '✓ Fertig: ${_resultFiles.length} Bild(er) in:\n$outDir');
    } catch (e) {
      _showError('Fehler beim Umwandeln: $e');
      setState(() => _statusText = 'Abgebrochen wegen Fehler.');
    } finally {
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

  /// Öffnet die gerade erzeugten Bilder in der App (alle Seiten, blätterbar).
  Future<void> _openResult() async {
    if (_resultFiles.isEmpty) return;
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
                ],
                selected: {_format},
                onSelectionChanged: _busy
                    ? null
                    : (s) => setState(() => _format = s.first),
              ),
              const SizedBox(height: 8),
              Text(
                _format == OutputFormat.png
                    ? 'PNG: verlustfrei, beste Schärfe, größere Dateien.'
                    : 'JPEG: kleinere Dateien, bei Text leichte Artefakte.',
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
          LinearProgressIndicator(value: _progress),
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
