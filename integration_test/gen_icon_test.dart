// Erzeugt das App-Icon mit der echten Flutter-Engine und speichert PNGs:
//   assets/icon/app_icon.png      – volles Icon (roter Hintergrund + weißer Inhalt)
//   assets/icon/app_icon_fg.png   – nur Inhalt auf transparent (Android-Adaptive-Vordergrund)
//
// Ausführen:  flutter test integration_test/gen_icon_test.dart -d windows

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _red = Color(0xFFC62828);

/// Das Logo: „PDF" (weiß) – Tausch-Pfeile – Bilderrahmen, untereinander.
Widget _logo({required bool withBackground, double scale = 1.0}) {
  final content = Column(
    mainAxisAlignment: MainAxisAlignment.center,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('PDF',
          style: TextStyle(
            color: Colors.white,
            fontSize: 250 * scale,
            fontWeight: FontWeight.w900,
            letterSpacing: 6 * scale,
            height: 1.0,
          )),
      SizedBox(height: 10 * scale),
      Icon(Icons.swap_vert, color: Colors.white, size: 200 * scale),
      SizedBox(height: 6 * scale),
      Icon(Icons.image_outlined, color: Colors.white, size: 300 * scale),
    ],
  );
  return Container(
    width: 1024,
    height: 1024,
    color: withBackground ? _red : const Color(0x00000000),
    alignment: Alignment.center,
    child: content,
  );
}

Future<void> _render(WidgetTester tester, Widget art, String path) async {
  final key = GlobalKey();
  tester.view.physicalSize = const Size(1024, 1024);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(key: key, child: art),
    ),
  );
  await tester.pumpAndSettle();

  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1.0);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(data!.buffer.asUint8List());
  // ignore: avoid_print
  print('Icon geschrieben: $path (${image.width}x${image.height})');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App-Icon erzeugen', (tester) async {
    final dir = Directory.current.path;
    await _render(tester, _logo(withBackground: true),
        '$dir/assets/icon/app_icon.png');
    // Vordergrund kleiner (Safe-Zone für Android-Adaptive-Icons).
    await _render(tester, _logo(withBackground: false, scale: 0.62),
        '$dir/assets/icon/app_icon_fg.png');
  });
}
