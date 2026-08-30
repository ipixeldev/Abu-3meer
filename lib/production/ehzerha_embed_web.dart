import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

class EhzerhaEmbed extends StatefulWidget {
  const EhzerhaEmbed({super.key});

  @override
  State<EhzerhaEmbed> createState() => _EhzerhaEmbedState();
}

class _EhzerhaEmbedState extends State<EhzerhaEmbed> {
  late final String viewType;

  @override
  void initState() {
    super.initState();
    viewType = 'ehzerha-${identityHashCode(this)}';
    ui_web.platformViewRegistry.registerViewFactory(viewType, (_) {
      final frame = web.HTMLIFrameElement()
        ..src = 'https://ehzerha-play.web.app/'
        ..title = 'Ehzerha game'
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%';
      frame.setAttribute(
        'allow',
        'fullscreen; autoplay; clipboard-read; clipboard-write',
      );
      return frame;
    });
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: viewType);
}
