import 'package:flutter/material.dart';

/// Ordnet Karten auf breiten (Desktop-)Fenstern zu zweit nebeneinander an,
/// um den Platz besser zu nutzen. Auf schmalen Fenstern/Handys bleibt es
/// bei einer Spalte untereinander.
class ResponsiveCards extends StatelessWidget {
  const ResponsiveCards({
    super.key,
    required this.children,
    this.enabled = true,
    this.spacing = 16,
    this.breakpoint = 560,
  });

  final List<Widget> children;
  final bool enabled;
  final double spacing;
  final double breakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final twoColumn = enabled && constraints.maxWidth >= breakpoint;
      if (!twoColumn) {
        final widgets = <Widget>[];
        for (var i = 0; i < children.length; i++) {
          widgets.add(children[i]);
          if (i != children.length - 1) {
            widgets.add(SizedBox(height: spacing));
          }
        }
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: widgets);
      }
      final columnWidth = (constraints.maxWidth - spacing) / 2;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final child in children)
            SizedBox(width: columnWidth, child: child),
        ],
      );
    });
  }
}
