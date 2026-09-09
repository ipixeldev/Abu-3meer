import 'package:flutter/material.dart';

import '../../production/app_preferences.dart';
import '../../production/brand.dart';
import '../../production/support_contact_service.dart';

/// No request is made until the user taps. An unset number never opens a dummy chat.
class WhatsAppSupportButton extends StatefulWidget {
  const WhatsAppSupportButton({super.key, this.service});
  final SupportContactService? service;

  @override
  State<WhatsAppSupportButton> createState() => _WhatsAppSupportButtonState();
}

class _WhatsAppSupportButtonState extends State<WhatsAppSupportButton> {
  bool _opening = false;

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    final result = await (widget.service ?? SupportContactService.instance)
        .openWhatsApp(isStillActive: () => mounted);
    if (!mounted) return;
    setState(() => _opening = false);
    if (result == SupportContactResult.opened) return;
    final message = switch (result) {
      SupportContactResult.notConfigured => abuText(
        context,
        'WhatsApp support is not available yet. Email ${AbuBrand.supportEmail}.',
        'دعم واتساب غير متاح بعد. راسل ${AbuBrand.supportEmail}.',
      ),
      SupportContactResult.launchFailed => abuText(
        context,
        'Could not open WhatsApp. Email ${AbuBrand.supportEmail}.',
        'تعذر فتح واتساب. راسل ${AbuBrand.supportEmail}.',
      ),
      _ => abuText(
        context,
        'Could not load the support contact. Try again or email ${AbuBrand.supportEmail}.',
        'تعذر تحميل جهة الدعم. حاول مجدداً أو راسل ${AbuBrand.supportEmail}.',
      ),
    };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: _opening ? null : _open,
    icon: _opening
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.chat_bubble_outline_rounded),
    label: Text(abuText(context, 'WhatsApp support', 'الدعم عبر واتساب')),
  );
}
