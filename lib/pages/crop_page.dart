import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';

/// Vollbild-Seite zum Zuschneiden eines Bildes.
/// Gibt die zugeschnittenen Bytes über Navigator.pop zurück (oder null bei Abbruch).
class CropPage extends StatefulWidget {
  const CropPage({super.key, required this.image});
  final Uint8List image;

  @override
  State<CropPage> createState() => _CropPageState();
}

class _CropPageState extends State<CropPage> {
  final _controller = CropController();
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Zuschneiden'),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(
              tooltip: 'Übernehmen',
              icon: const Icon(Icons.check),
              onPressed: () {
                setState(() => _busy = true);
                _controller.crop();
              },
            ),
        ],
      ),
      body: Crop(
        image: widget.image,
        controller: _controller,
        baseColor: Colors.black,
        maskColor: Colors.black.withValues(alpha: 0.6),
        onCropped: (result) {
          switch (result) {
            case CropSuccess(:final croppedImage):
              if (mounted) Navigator.pop(context, croppedImage);
            case CropFailure():
              if (mounted) {
                setState(() => _busy = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Zuschneiden fehlgeschlagen.')),
                );
              }
          }
        },
      ),
    );
  }
}
