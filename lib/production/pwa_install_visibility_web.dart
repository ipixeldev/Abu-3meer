import 'package:web/web.dart' as web;

void setObsOverlayActive(bool active) {
  web.document.body?.classList.toggle('obs-active', active);
}
