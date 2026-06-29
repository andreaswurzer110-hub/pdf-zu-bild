import 'package:flutter/material.dart';

import 'license_service.dart';
import 'widgets/paywall_dialog.dart';

/// Prüft vor einer Umwandlung, ob noch ein Gratis-Kontingent da ist.
/// Ist es aufgebraucht, wird die Paywall gezeigt. Rückgabe: true = weitermachen.
Future<bool> ensureCanConvert(BuildContext context) async {
  final lic = LicenseService.instance;
  if (!lic.isLocked) return true;
  await showPaywall(context);
  // Falls während der Paywall gekauft wurde, ist die Sperre nun weg.
  return !LicenseService.instance.isLocked;
}

/// Kleiner Hinweis „Noch X von Y gratis"; verschwindet in der Vollversion.
class RemainingFreeBadge extends StatelessWidget {
  const RemainingFreeBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LicenseService.instance,
      builder: (context, _) {
        final lic = LicenseService.instance;
        if (lic.isPro) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.info_outline, size: 16, color: scheme.outline),
              const SizedBox(width: 6),
              Text(
                'Noch ${lic.remainingFree} von ${LicenseService.freeLimit} '
                'kostenlosen Umwandlungen',
                style: TextStyle(fontSize: 12, color: scheme.outline),
              ),
            ],
          ),
        );
      },
    );
  }
}
