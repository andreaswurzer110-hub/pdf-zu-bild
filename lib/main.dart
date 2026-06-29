import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:pdfx/pdfx.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  runApp(const PdfZuBildApp());
}

class PdfZuBildApp extends StatelessWidget {
  const PdfZuBildApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDF zu Bild',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFC62828)),
      ),
      home: const HomePage(),
    );
  }
}

enum OutputFormat { png, jpeg }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Ausgewähltes PDF
  String? _pdfPath;
  int _pageCount = 0;

  // Einstellungen
  int _dpi = 300;
  OutputFormat _format = OutputFormat.png;
  int _jpegQuality = 92;
  bool _allPages = true;
  final TextEditingController _pageRangeController = TextEditingController();
  String? _outputDir;

  // Status
  bool _busy = false;
  double _progress = 0;
  String _statusText = '';
  final List<String> _resultFiles = [];

  final TextEditingController _dpiController =
      TextEditingController(text: '300');

  @override
  void dispose() {
    _pageRangeController.dispose();
    _dpiController.dispose();
    super.dispose();
  }

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result == null || result.files.single.path == null) return;
    final path = result.files.single.path!;

    int pages = 0;
    try {
      final doc = await PdfDocument.openFile(path);
      pages = doc.pagesCount;
      await doc.close();
    } catch (e) {
      _showError('PDF konnte nicht geöffnet werden: $e');
      return;
    }

    setState(() {
      _pdfPath = path;
      _pageCount = pages;
      _resultFiles.clear();
      _statusText = '';
      _outputDir ??= p.dirname(path);
    });
  }

  Future<void> _pickOutputDir() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir != null) {
      setState(() => _outputDir = dir);
    }
  }

  /// Wandelt eine Seitenangabe wie "1-3,5,8-10" in eine sortierte Seitenliste.
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

    // Welche Seiten?
    List<int> targetPages;
    if (_allPages) {
      targetPages = [for (int i = 1; i <= _pageCount; i++) i];
    } else {
      targetPages = _parsePageRange(_pageRangeController.text, _pageCount);
      if (targetPages.isEmpty) {
        _showError(
            'Keine gültigen Seiten angegeben. Beispiel: 1-3,5 (PDF hat $_pageCount Seiten).');
        return;
      }
    }

    final outDir = _outputDir ?? p.dirname(_pdfPath!);
    final baseName = p.basenameWithoutExtension(_pdfPath!);
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
        setState(() {
          _statusText =
              'Seite $pageNo wird umgewandelt … (${idx + 1}/${targetPages.length})';
        });

        final page = await doc.getPage(pageNo);
        // page.width/height sind in PDF-Punkten (72 pt = 1 Zoll).
        final double pxWidth = page.width * _dpi / 72.0;
        final double pxHeight = page.height * _dpi / 72.0;

        final image = await page.render(
          width: pxWidth,
          height: pxHeight,
          format: isPng ? PdfPageImageFormat.png : PdfPageImageFormat.jpeg,
          backgroundColor: '#FFFFFF',
          quality: isPng ? 100 : _jpegQuality,
        );
        await page.close();

        if (image == null) {
          throw Exception('Seite $pageNo konnte nicht gerendert werden.');
        }

        final fileName =
            '${baseName}_Seite_${pageNo.toString().padLeft(pad, '0')}.$ext';
        final outPath = p.join(outDir, fileName);
        await File(outPath).writeAsBytes(image.bytes);
        _resultFiles.add(outPath);

        setState(() {
          _progress = (idx + 1) / targetPages.length;
        });
      }

      setState(() {
        _statusText =
            '✓ Fertig: ${_resultFiles.length} Bild(er) gespeichert in:\n$outDir';
      });
    } catch (e) {
      _showError('Fehler beim Umwandeln: $e');
      setState(() => _statusText = 'Abgebrochen wegen Fehler.');
    } finally {
      await doc?.close();
      setState(() => _busy = false);
    }
  }

  Future<void> _shareResults() async {
    if (_resultFiles.isEmpty) return;
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: _resultFiles.map((f) => XFile(f)).toList(),
          text: 'Umgewandelte PDF-Seiten',
        ),
      );
    } catch (e) {
      _showError('Teilen nicht möglich: $e');
    }
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasPdf = _pdfPath != null;
    final canShare = _resultFiles.isNotEmpty && !_busy;

    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF zu Bild'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // 1. PDF auswählen
              _SectionCard(
                title: '1. PDF auswählen',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FilledButton.icon(
                      onPressed: _busy ? null : _pickPdf,
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('PDF-Datei wählen'),
                    ),
                    if (hasPdf) ...[
                      const SizedBox(height: 12),
                      Text(p.basename(_pdfPath!),
                          style:
                              const TextStyle(fontWeight: FontWeight.bold)),
                      Text('$_pageCount Seite(n)'),
                    ],
                  ],
                ),
              ),

              // 2. Qualität (DPI)
              _SectionCard(
                title: '2. Qualität (DPI)',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Slider(
                            value: _dpi.toDouble().clamp(72, 600),
                            min: 72,
                            max: 600,
                            divisions: (600 - 72) ~/ 6,
                            label: '$_dpi dpi',
                            onChanged: _busy
                                ? null
                                : (v) {
                                    setState(() {
                                      _dpi = v.round();
                                      _dpiController.text = '$_dpi';
                                    });
                                  },
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
                          padding: EdgeInsets.only(left: 4),
                          child: Text('dpi'),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      children: [150, 300, 400, 600]
                          .map((d) => ActionChip(
                                label: Text('$d'),
                                onPressed: _busy
                                    ? null
                                    : () {
                                        setState(() {
                                          _dpi = d;
                                          _dpiController.text = '$d';
                                        });
                                      },
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

              // 3. Format
              _SectionCard(
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
                      Row(
                        children: [
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
                                  : (v) => setState(
                                      () => _jpegQuality = v.round()),
                            ),
                          ),
                          Text('$_jpegQuality'),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // 4. Seitenauswahl
              _SectionCard(
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
                      child: const Column(
                        children: [
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
                        ],
                      ),
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

              // 5. Zielordner
              _SectionCard(
                title: '5. Zielordner',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _pickOutputDir,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Ordner wählen'),
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

              const SizedBox(height: 8),

              // Umwandeln-Button
              FilledButton.icon(
                onPressed: (hasPdf && !_busy) ? _convert : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.auto_awesome),
                label: Text(_busy ? 'Wird umgewandelt …' : 'Umwandeln'),
              ),

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
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_statusText),
                ),
              ],

              if (canShare) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: _shareResults,
                        icon: const Icon(Icons.share),
                        label: const Text('Teilen / WhatsApp'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (Platform.isWindows || Platform.isLinux)
                      OutlinedButton.icon(
                        onPressed: _openOutputFolder,
                        icon: const Icon(Icons.folder),
                        label: const Text('Ordner öffnen'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

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
