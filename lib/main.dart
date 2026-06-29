import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'app_mode.dart';
import 'license_service.dart';
import 'opened_file.dart';
import 'purchase_service.dart';
import 'pages/image_to_pdf_page.dart';
import 'pages/image_viewer_page.dart';
import 'pages/pdf_reader_page.dart';
import 'pages/pdf_to_image_page.dart';
import 'widgets/mode_toggle.dart';
import 'widgets/paywall_dialog.dart';
import 'widgets/redeem_code_dialog.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lizenz-/Kauf-Status laden (Gratis-Zähler, Vollversion).
  await LicenseService.instance.init();
  await PurchaseService.instance.init();

  // Per „Öffnen mit" übergebene PDF ermitteln (Desktop: Argumente, Android: Channel).
  String? openedPdf = OpenedFile.fromArgs(args);
  openedPdf ??= await OpenedFile.fromAndroid();

  runApp(PdfZuBildApp(openedPdfPath: openedPdf));
}

class PdfZuBildApp extends StatelessWidget {
  const PdfZuBildApp({super.key, this.openedPdfPath});
  final String? openedPdfPath;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDF zu Bild',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFC62828)),
      ),
      home: AppShell(openedPdfPath: openedPdfPath),
    );
  }
}

enum _View { reader, pdfToImage, imageToPdf }

class AppShell extends StatefulWidget {
  const AppShell({super.key, this.openedPdfPath});
  final String? openedPdfPath;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late _View _view;
  String? _readerPath;

  @override
  void initState() {
    super.initState();
    _readerPath = widget.openedPdfPath;
    _view = _readerPath != null ? _View.reader : _View.pdfToImage;
  }

  AppMode get _toggleMode =>
      _view == _View.imageToPdf ? AppMode.imageToPdf : AppMode.pdfToImage;

  void _onModeChanged(AppMode mode) {
    setState(() {
      _view = mode == AppMode.imageToPdf
          ? _View.imageToPdf
          : _View.pdfToImage;
    });
  }

  /// Datei öffnen: PDF → Reader, Bild → Bildanzeige.
  Future<void> _openFile() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'],
    );
    final path = res?.files.single.path;
    if (path == null) return;

    if (p.extension(path).toLowerCase() == '.pdf') {
      setState(() {
        _readerPath = path;
        _view = _View.reader;
      });
    } else if (mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ImageViewerPage(path: path)),
      );
    }
  }

  void _onMenu(String value) {
    switch (value) {
      case 'code':
        showRedeemCodeDialog(context);
        break;
      case 'buy':
        showPaywall(context);
        break;
      case 'restore':
        PurchaseService.instance.restore();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final Widget body;
    if (_view == _View.reader && _readerPath != null) {
      body = PdfReaderPage(path: _readerPath!);
    } else {
      // Beide Modi am Leben halten, damit Eingaben beim Umschalten bleiben.
      body = IndexedStack(
        index: _view == _View.imageToPdf ? 1 : 0,
        children: [
          PdfToImagePage(initialPdfPath: widget.openedPdfPath),
          const ImageToPdfPage(),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        title: ModeToggle(mode: _toggleMode, onChanged: _onModeChanged),
        actions: [
          ListenableBuilder(
            listenable: LicenseService.instance,
            builder: (context, _) {
              final isPro = LicenseService.instance.isPro;
              return PopupMenuButton<String>(
                onSelected: _onMenu,
                itemBuilder: (context) => [
                  if (!isPro)
                    const PopupMenuItem(
                        value: 'buy', child: Text('Vollversion kaufen')),
                  if (!isPro)
                    const PopupMenuItem(
                        value: 'code', child: Text('Code einlösen')),
                  if (!isPro)
                    const PopupMenuItem(
                        value: 'restore',
                        child: Text('Käufe wiederherstellen')),
                  if (isPro)
                    const PopupMenuItem(
                        value: 'pro',
                        enabled: false,
                        child: Text('✓ Vollversion aktiv')),
                ],
              );
            },
          ),
        ],
      ),
      body: SafeArea(child: body),
      // Unten: Datei öffnen (PDF → Reader, Bild → Anzeige). In den Umwandel-Modi.
      bottomNavigationBar: _view == _View.reader
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                child: OutlinedButton.icon(
                  onPressed: _openFile,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                  ),
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Öffnen (PDF im Reader / Bild anzeigen)'),
                ),
              ),
            ),
    );
  }
}
