import 'package:flutter/material.dart';

import '../license_service.dart';

/// Dialog zum Freischalten der Vollversion per Code.
Future<void> showRedeemCodeDialog(BuildContext context) {
  return showDialog(
    context: context,
    builder: (_) => const RedeemCodeDialog(),
  );
}

class RedeemCodeDialog extends StatefulWidget {
  const RedeemCodeDialog({super.key});

  @override
  State<RedeemCodeDialog> createState() => _RedeemCodeDialogState();
}

class _RedeemCodeDialogState extends State<RedeemCodeDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final ok = await LicenseService.instance.redeemCode(_controller.text);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✓ Vollversion freigeschaltet')),
      );
    } else {
      setState(() => _error = 'Code ungültig.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Code einlösen'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: 'Freischalt-Code',
          errorText: _error,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Freischalten')),
      ],
    );
  }
}
