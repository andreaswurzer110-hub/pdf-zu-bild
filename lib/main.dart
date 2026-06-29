import 'package:flutter/material.dart';

import 'app_mode.dart';
import 'opened_file.dart';
import 'pages/image_to_pdf_page.dart';
import 'pages/pdf_reader_page.dart';
import 'pages/pdf_to_image_page.dart';
import 'widgets/mode_toggle.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

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

  @override
  void initState() {
    super.initState();
    _view = widget.openedPdfPath != null ? _View.reader : _View.pdfToImage;
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final Widget body;
    if (_view == _View.reader) {
      body = PdfReaderPage(path: widget.openedPdfPath!);
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
      ),
      body: SafeArea(child: body),
    );
  }
}
