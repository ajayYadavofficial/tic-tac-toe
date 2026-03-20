import 'dart:js_interop';
import 'package:web/web.dart' as web;

import 'nakama_client.dart';

/// On web: register beforeunload to logout when browser tab/window closes.
void setupWebBeforeUnload() {
  web.window.onbeforeunload = ((web.BeforeUnloadEvent event) {
    NakamaGameClient.instance.logout();
  }).toJS;
}
