import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class EhzerhaEmbed extends StatelessWidget {
  const EhzerhaEmbed({super.key});

  static final Uri gameUri = Uri.parse('https://ehzerha-play.web.app/');

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFF11161E),
    child: Center(
      child: FilledButton.icon(
        onPressed: () =>
            launchUrl(gameUri, mode: LaunchMode.externalApplication),
        icon: const Icon(Icons.open_in_new_rounded),
        label: const Text('OPEN EHZERHA'),
      ),
    ),
  );
}
