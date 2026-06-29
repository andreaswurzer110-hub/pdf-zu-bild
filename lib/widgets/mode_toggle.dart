import 'package:flutter/material.dart';

import '../app_mode.dart';

/// Umschalter im Titel: „PDF  ⇅  Bild".
/// Links/rechts wählen die Richtung, das Pfeil-Symbol in der Mitte tauscht sie.
class ModeToggle extends StatelessWidget {
  const ModeToggle({super.key, required this.mode, required this.onChanged});

  final AppMode mode;
  final ValueChanged<AppMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isPdf = mode == AppMode.pdfToImage;

    Widget side(String text, bool active) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? scheme.onPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: active ? scheme.primary : scheme.onPrimary,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => onChanged(AppMode.pdfToImage),
            child: side('PDF', isPdf),
          ),
          // Tausch-Symbol (zwei Pfeile in Gegenrichtung).
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Richtung tauschen',
            icon: Icon(Icons.swap_horiz, color: scheme.onPrimary),
            onPressed: () => onChanged(
              isPdf ? AppMode.imageToPdf : AppMode.pdfToImage,
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => onChanged(AppMode.imageToPdf),
            child: side('Bild', !isPdf),
          ),
        ],
      ),
    );
  }
}
