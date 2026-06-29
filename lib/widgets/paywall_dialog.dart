import 'package:flutter/material.dart';

import '../license_service.dart';
import '../purchase_service.dart';
import 'redeem_code_dialog.dart';

/// Zeigt die Paywall. Schließt sich automatisch, sobald freigeschaltet wurde.
Future<void> showPaywall(BuildContext context) {
  return showDialog(
    context: context,
    builder: (_) => const PaywallDialog(),
  );
}

class PaywallDialog extends StatefulWidget {
  const PaywallDialog({super.key});

  @override
  State<PaywallDialog> createState() => _PaywallDialogState();
}

class _PaywallDialogState extends State<PaywallDialog> {
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    LicenseService.instance.addListener(_onLicense);
  }

  @override
  void dispose() {
    LicenseService.instance.removeListener(_onLicense);
    super.dispose();
  }

  void _onLicense() {
    // Nach erfolgreichem Kauf automatisch schließen.
    if (LicenseService.instance.isPro && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _buy() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final result = await PurchaseService.instance.buy();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = result; // null = Kauf gestartet (Ergebnis kommt per Stream)
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final price = PurchaseService.instance.displayPrice;

    return AlertDialog(
      icon: Icon(Icons.workspace_premium, color: scheme.primary, size: 40),
      title: const Text('Vollversion freischalten'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Du hast deine ${LicenseService.freeLimit} kostenlosen '
            'Umwandlungen aufgebraucht.\n\n'
            'Schalte die Vollversion für $price frei und wandle '
            'unbegrenzt um – einmalig zahlen, dauerhaft nutzen.',
            textAlign: TextAlign.center,
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(_message!,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.error, fontSize: 13)),
          ],
        ],
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: _busy ? null : () => showRedeemCodeDialog(context),
          child: const Text('Code einlösen'),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Später'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _busy ? null : _buy,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.lock_open),
              label: Text('Für $price kaufen'),
            ),
          ],
        ),
      ],
    );
  }
}
