class GameTemplate {
  final int id;          // unique integer, used to scope matchmaking
  final String variant;  // game-mode string (e.g. "classic", "blitz")
  final String name;
  final String description;
  final int minPlayers;
  final int maxPlayers;
  final int turnSecs;    // 0 = no timer, >0 = seconds per turn

  const GameTemplate({
    required this.id,
    required this.variant,
    required this.name,
    required this.description,
    required this.minPlayers,
    required this.maxPlayers,
    this.turnSecs = 0,
  });

  factory GameTemplate.fromJson(Map<String, dynamic> json) => GameTemplate(
        id: (json['id'] as num).toInt(),
        variant: json['variant'] as String,
        name: json['name'] as String,
        description: json['description'] as String,
        minPlayers: (json['min_players'] as num).toInt(),
        maxPlayers: (json['max_players'] as num).toInt(),
        turnSecs: (json['turn_secs'] as num?)?.toInt() ?? 0,
      );
}
