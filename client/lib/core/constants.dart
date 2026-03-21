class AppConstants {
  // Nakama server — override via: flutter run --dart-define=NAKAMA_HOST=...
  static const String nakamaHost =
      String.fromEnvironment('NAKAMA_HOST', defaultValue: 'localhost');
  static const int nakamaHttpPort = int.fromEnvironment(
      'NAKAMA_HTTP_PORT', defaultValue: 7350);
  static const bool nakamaSSL =
      bool.fromEnvironment('NAKAMA_SSL', defaultValue: false);
  static const String nakamaServerKey =
      String.fromEnvironment('NAKAMA_SERVER_KEY', defaultValue: 'defaultkey');

  // WebSocket opcodes — must match server/internal/game/constants.go
  static const int opCodeMove   = 1;
  static const int opCodeState  = 2;
  static const int opCodeResult = 3;
  static const int opCodeError  = 4;
  static const int opCodeResign = 5;
}
