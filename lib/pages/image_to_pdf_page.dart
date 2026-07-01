import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../file_naming.dart';
import '../image_processing.dart';
import '../license_service.dart';
import '../open_in_app.dart';
import '../pdf_builder.dart';
import '../usage_gate.dart';
import '../widgets/responsive_cards.dart';
import 'crop_page.dart';

/// Ein Bild in der Liste (Original + optional zugeschnittene Variante).
class _ImageItem {
  _ImageItem(this.name, this.original);
  final String name;
  final Uint8List original;
  Uint8List? cropped;
  Uint8List get current => cropped ?? original;
}

/// compute()-Helfer: wendet den Farbmodus in einem Hintergrund-Isolate an.
Uint8List _processEntry((Uint8List, ColorMode) e) => processImage(e.$1, e.$2);

/// Modus „Bild → PDF": Bilder/Kamera wählen, zuschneiden, Farbmodus, als PDF.
class ImageToPdfPage extends StatefulWidget {
  const ImageToPdfPage({super.key});

  @override
  State<ImageToPdfPage> createState() => ImageToPdfPageState();
}

class ImageToPdfPageState extends State<ImageToPdfPage> {
  final List<_ImageItem> _items = [];
  ColorMode _colorMode = ColorMode.original;
  bool _busy = false;
  String _statusText = '';
  String? _resultPdfPath;
  String? _outputDir;
  final _fileNameController = TextEditingController();
  final _scrollController = ScrollController();

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;
  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  void dispose() {
    _fileNameController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Von außen (Öffnen-Knopf oben) Bilder vorauswählen/hinzufügen.
  Future<void> addImagesFromPaths(List<String> paths) async {
    for (final path in paths) {
      try {
        final bytes = await File(path).readAsBytes();
        _items.add(_ImageItem(p.basename(path), bytes));
      } catch (_) {}
    }
    if (mounted) setState(() => _resultPdfPath = null);
  }

  Future<void> _pickImages() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );
    if (result == null) return;
    for (final f in result.files) {
      if (f.path == null) continue;
      final bytes = await File(f.path!).readAsBytes();
      _items.add(_ImageItem(f.name, bytes));
    }
    setState(() => _resultPdfPath = null);
  }

  Future<void> _takePhoto() async {
    try {
      final picker = ImagePicker();
      final shot = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 100,
      );
      if (shot == null) return;
      final bytes = await shot.readAsBytes();
      setState(() {
        _items.add(_ImageItem(p.basename(shot.path), bytes));
        _resultPdfPath = null;
      });
    } catch (e) {
      _showError('Kamera nicht verfügbar: $e');
    }
  }

  Future<void> _cropItem(int index) async {
    final item = _items[index];
    final cropped = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => CropPage(image: item.current)),
    );
    if (cropped != null) {
      setState(() {
        item.cropped = cropped;
        _resultPdfPath = null;
      });
    }
  }

  Future<void> _createPdf() async {
    if (_items.isEmpty) return;

    // Gratis-Kontingent prüfen (Paywall, falls aufgebraucht).
    if (!await ensureCanConvert(context)) return;

    setState(() {
      _busy = true;
      _statusText = 'Bilder werden aufbereitet …';
      _resultPdfPath = null;
    });

    try {
      // Farbmodus pro Bild anwenden (im Hintergrund-Isolate).
      final processed = <Uint8List>[];
      for (int i = 0; i < _items.length; i++) {
        setState(() => _statusText =
            'Bild ${i + 1}/${_items.length} wird aufbereitet …');
        final bytes = _colorMode == ColorMode.original
            ? _items[i].current
            : await compute(_processEntry, (_items[i].current, _colorMode));
        processed.add(bytes);
      }

      setState(() => _statusText = 'PDF wird erstellt …');
      final pdfBytes = await buildPdfFromImages(processed);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final customName = sanitizeFileName(_fileNameController.text);
      final fileBase = customName.isEmpty ? 'Dokument_$stamp' : customName;

      await LicenseService.instance.registerConversion();

      if (_outputDir != null) {
        // In den gewählten Zielordner speichern.
        final outPath = p.join(_outputDir!, '$fileBase.pdf');
        await File(outPath).writeAsBytes(pdfBytes);
        setState(() {
          _resultPdfPath = outPath;
          _statusText = '✓ PDF mit ${processed.length} Seite(n) '
              'gespeichert in:\n$_outputDir';
        });
      } else {
        // Kein Zielordner: temporär ablegen (zum Teilen) …
        final dir = await getTemporaryDirectory();
        final tmpPath = p.join(dir.path, '$fileBase.pdf');
        await File(tmpPath).writeAsBytes(pdfBytes);
        setState(() {
          _resultPdfPath = tmpPath;
          _statusText = '✓ PDF mit ${processed.length} Seite(n) erstellt.';
        });
        // … und auf dem Desktop direkt „Speichern unter…" anbieten.
        if (_isDesktop) await _saveAs(pdfBytes, suggestedName: '$fileBase.pdf');
      }
    } catch (e) {
      _showError('Fehler beim Erstellen: $e');
      setState(() => _statusText = 'Abgebrochen wegen Fehler.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveAs(Uint8List pdfBytes, {String suggestedName = 'Dokument.pdf'}) async {
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'PDF speichern',
        fileName: suggestedName,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        bytes: pdfBytes,
      );
      // Unter Desktop schreibt file_picker nicht selbst – Bytes manuell sichern.
      if (path != null) {
        final f = File(path);
        if (!await f.exists() || await f.length() == 0) {
          await f.writeAsBytes(pdfBytes);
        }
        setState(() => _statusText = '✓ Gespeichert: $path');
      }
    } catch (e) {
      _showError('Speichern nicht möglich: $e');
    }
  }

  Future<void> _pickOutputDir() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir != null) setState(() => _outputDir = dir);
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

  /// Öffnet das gerade erzeugte PDF im Reader.
  Future<void> _openResult() async {
    if (_resultPdfPath == null) return;
    await openPathInApp(context, _resultPdfPath!);
  }

  Future<void> _share() async {
    if (_resultPdfPath == null) return;
    try {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(_resultPdfPath!)], text: 'PDF-Dokument'),
      );
    } catch (e) {
      _showError('Teilen nicht möglich: $e');
    }
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
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: _isDesktop ? 1000 : 640),
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: _isDesktop,
          child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.all(20),
          children: [
            ResponsiveCards(
              enabled: _isDesktop,
              children: [
            _Card(
              title: '1. Bilder hinzufügen',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _busy ? null : _pickImages,
                        icon: const Icon(Icons.add_photo_alternate),
                        label: const Text('Bilder wählen'),
                      ),
                      if (_isMobile)
                        FilledButton.tonalIcon(
                          onPressed: _busy ? null : _takePhoto,
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('Kamera'),
                        ),
                    ],
                  ),
                  if (_items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text('Noch keine Bilder ausgewählt.',
                          style: TextStyle(color: scheme.outline)),
                    ),
                ],
              ),
            ),
            if (_items.isNotEmpty)
              _Card(
                title: '2. Reihenfolge / Zuschneiden',
                child: Column(
                  children: [
                    Text(
                      'Tippen zum Zuschneiden, am Griff ziehen zum Sortieren.',
                      style: TextStyle(fontSize: 12, color: scheme.outline),
                    ),
                    const SizedBox(height: 8),
                    ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      // Kein automatischer Drag-Griff auf der ganzen Zeile –
                      // sonst schluckt der Drag auf dem Desktop die Taps auf die
                      // Zuschneiden-/Entfernen-Buttons. Stattdessen ein eigener
                      // Griff (unten, ReorderableDragStartListener).
                      buildDefaultDragHandles: false,
                      itemCount: _items.length,
                      onReorderItem: (oldI, newI) {
                        setState(() {
                          final it = _items.removeAt(oldI);
                          _items.insert(newI, it);
                          _resultPdfPath = null;
                        });
                      },
                      itemBuilder: (context, i) {
                        final item = _items[i];
                        return ListTile(
                          key: ValueKey(item),
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.memory(item.current,
                                width: 48, height: 48, fit: BoxFit.cover),
                          ),
                          title: Text('Seite ${i + 1}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold)),
                          subtitle: Text(
                            item.cropped != null
                                ? 'zugeschnitten'
                                : item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: _busy ? null : () => _cropItem(i),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Zuschneiden',
                                icon: const Icon(Icons.crop),
                                onPressed:
                                    _busy ? null : () => _cropItem(i),
                              ),
                              IconButton(
                                tooltip: 'Entfernen',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: _busy
                                    ? null
                                    : () => setState(() {
                                          _items.removeAt(i);
                                          _resultPdfPath = null;
                                        }),
                              ),
                              // Eigener Anfasser zum Sortieren (Drag).
                              ReorderableDragStartListener(
                                index: i,
                                enabled: !_busy,
                                child: const Padding(
                                  padding: EdgeInsets.only(left: 4, right: 4),
                                  child: Icon(Icons.drag_handle),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            if (_items.isNotEmpty)
              _Card(
                title: '3. Darstellung',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SegmentedButton<ColorMode>(
                      segments: ColorMode.values
                          .map((m) => ButtonSegment(
                              value: m, label: Text(m.label)))
                          .toList(),
                      selected: {_colorMode},
                      onSelectionChanged: _busy
                          ? null
                          : (s) => setState(() {
                                _colorMode = s.first;
                                _resultPdfPath = null;
                              }),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      switch (_colorMode) {
                        ColorMode.original =>
                          'Farben bleiben unverändert.',
                        ColorMode.grayscale =>
                          'In Graustufen umgewandelt.',
                        ColorMode.scan =>
                          'Wie eingescannt: heller Hintergrund, kräftiger Text.',
                      },
                      style: TextStyle(fontSize: 12, color: scheme.outline),
                    ),
                  ],
                ),
              ),
            if (_items.isNotEmpty)
              _Card(
                title: '4. Zielordner & Name',
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
                              hintText: 'Dokument',
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _outputDir ??
                          (_isDesktop
                              ? 'Standard: wird beim Speichern gefragt'
                              : 'Standard: über „Teilen" weitergeben'),
                      style: TextStyle(fontSize: 12, color: scheme.outline),
                    ),
                  ],
                ),
              ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: (_items.isNotEmpty && !_busy) ? _createPdf : null,
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.picture_as_pdf),
              label: Text(_busy ? 'Wird erstellt …' : 'Als PDF erstellen'),
            ),
            const RemainingFreeBadge(),
            if (_statusText.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_statusText),
              ),
            ],
            if (_resultPdfPath != null && !_busy) ...[
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _share,
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(46)),
                    icon: const Icon(Icons.share),
                    label: const Text('Teilen / WhatsApp'),
                  ),
                ),
                const SizedBox(width: 12),
                // Öffnet nur das gerade erzeugte PDF im Reader.
                OutlinedButton.icon(
                  onPressed: _openResult,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Öffnen'),
                ),
              ]),
              if (_isDesktop) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        final bytes =
                            await File(_resultPdfPath!).readAsBytes();
                        await _saveAs(bytes,
                            suggestedName: p.basename(_resultPdfPath!));
                      },
                      icon: const Icon(Icons.save_alt),
                      label: const Text('Speichern unter…'),
                    ),
                    if (_outputDir != null)
                      OutlinedButton.icon(
                        onPressed: _openOutputFolder,
                        icon: const Icon(Icons.folder),
                        label: const Text('Ordner öffnen'),
                      ),
                  ],
                ),
              ],
            ],
          ],
          ),
        ),
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
