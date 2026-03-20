# Multiplayer Tic-Tac-Toe

Real-time multiplayer Tic-Tac-Toe built with **Nakama** (game server), **Go** (server-side game logic), and **Flutter** (cross-platform client).

## Architecture

```
┌─────────────────┐         WebSocket / HTTP         ┌──────────────────┐
│  Flutter Client  │ ◄──────────────────────────────► │   Nakama Server  │
│  (Web / Mobile)  │                                  │   + Go Plugin    │
└─────────────────┘                                  └────────┬─────────┘
                                                              │
                                                     ┌────────▼─────────┐
                                                     │   PostgreSQL 15  │
                                                     └──────────────────┘
```

**Server (Go plugin)** — Authoritative match handler, matchmaking, RPCs for stats/leaderboard.
**Client (Flutter)** — Nickname entry, lobby, matchmaking, game board, result screen with leaderboard.

## Features

- **Device-based auth** — no passwords, automatic session restore on return visits
- **Template-based matchmaking** — players pick a game mode, server pairs them
- **Server-authoritative** — all moves validated server-side, no cheating
- **Real-time WebSocket** — instant move updates, state broadcasts
- **Leaderboard & stats** — wins/losses/draws/score tracked per player
- **Timer support** — infrastructure for timed modes (Blitz, Standard)
- **Auto-reconnect** — exponential backoff on disconnect
- **Disconnect forfeit** — 30-second grace period, then auto-forfeit

## Tech Stack

| Layer    | Technology                     |
|----------|--------------------------------|
| Backend  | Go 1.22 (Nakama runtime plugin)|
| Server   | Nakama 3.22.0                  |
| Database | PostgreSQL 15                  |
| Frontend | Flutter (web + mobile)         |
| Infra    | Docker Compose                 |

## Project Structure

```
tic-tac-toe/
├── server/                    # Go plugin
│   ├── main.go                # InitModule: RPCs, match registration
│   └── internal/
│       ├── game/
│       │   ├── constants.go   # Opcodes, scoring, storage keys
│       │   ├── templates.go   # Game templates (Classic, Blitz, etc.)
│       │   ├── state.go       # MatchState, wire message structs
│       │   ├── logic.go       # ValidateMove, ApplyMove, GetGameResult
│       │   └── logic_test.go  # Unit tests for game logic
│       └── match/
│           ├── handler.go     # Nakama Match interface (Init, Join, Loop, etc.)
│           ├── hooks.go       # OnMatchEnd: stats + leaderboard writes
│           └── matchmaking.go # OnMatchmakerMatched: create match from template
├── client/                    # Flutter app
│   └── lib/
│       ├── core/
│       │   ├── constants.dart # Server config (overridable via --dart-define)
│       │   └── nakama_client.dart  # Auth, socket, RPCs, reconnection
│       ├── models/
│       │   ├── game_state.dart     # GameState, GameResult, PlayerStats
│       │   └── game_template.dart  # GameTemplate model
│       └── screens/
│           ├── nickname_screen.dart    # First-launch name entry
│           ├── lobby_screen.dart       # Template cards + stats
│           ├── matchmaking_screen.dart # Spinner while finding opponent
│           ├── game_screen.dart        # Live game board
│           └── result_screen.dart      # Win/loss + leaderboard
├── deploy/                    # Production deployment
│   ├── Dockerfile.nakama      # Multi-stage Go plugin build
│   ├── Dockerfile.web         # Flutter web + nginx
│   ├── docker-compose.prod.yml
│   ├── nginx.conf
│   └── deploy.sh
├── docker-compose.yml         # Local development
└── README.md
```

## Quick Start (Local Development)

### Prerequisites

- [Docker](https://docs.docker.com/get-docker/) & Docker Compose
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.x+)
- [Go 1.22+](https://go.dev/dl/) (only needed if modifying server code)

### 1. Start Nakama + PostgreSQL

```bash
# Build the Go plugin for Linux (required for Docker)
docker run --rm \
  -v "$PWD/server":/backend \
  -w /backend \
  heroiclabs/nakama-pluginbuilder:3.22.0 \
  build -buildmode=plugin -trimpath -o /backend/modules/tictactoe.so .

# Start services
docker compose up -d
```

Nakama console: http://localhost:7351 (admin/password)

### 2. Run the Flutter Client

```bash
cd client
flutter pub get
flutter run -d chrome
```

The client connects to `localhost:7350` by default. Override with:
```bash
flutter run -d chrome \
  --dart-define=NAKAMA_HOST=your-server.com \
  --dart-define=NAKAMA_HTTP_PORT=7350 \
  --dart-define=NAKAMA_SSL=true
```

### 3. Play

1. Open two browser tabs
2. Enter a nickname in each
3. Both tap "Play" on the Classic template
4. Matchmaker pairs them — game begins!

## Production Deployment

```bash
# Set your domain and DB password
export DOMAIN=play.example.com
export POSTGRES_PASSWORD=your-secure-password

# Build and deploy
./deploy/deploy.sh
```

Or step by step:

```bash
# 1. Build Go plugin
docker build -f deploy/Dockerfile.nakama -t ttt-nakama ./server

# 2. Build Flutter web
cd client && flutter build web --release \
  --dart-define=NAKAMA_HOST=play.example.com \
  --dart-define=NAKAMA_HTTP_PORT=80 \
  --dart-define=NAKAMA_SSL=false
cd ..

# 3. Start
docker compose -f deploy/docker-compose.prod.yml up -d
```

## Server RPCs

| RPC                | Auth | Description                            |
|--------------------|------|----------------------------------------|
| `create_match`     | Yes  | Create a new match (returns match_id)  |
| `list_matches`     | Yes  | List open matches waiting for players  |
| `list_templates`   | Yes  | Get available game templates           |
| `update_username`  | Yes  | Set player display name                |
| `release_username` | Yes  | Free username on logout                |
| `player_stats`     | Yes  | Get caller's win/loss/draw/score       |
| `get_leaderboard`  | Yes  | Top 20 players by score                |

## WebSocket OpCodes

| Code | Direction       | Description                  |
|------|-----------------|------------------------------|
| 1    | Client → Server | Send move (position 0-8)     |
| 2    | Server → Client | Game state update            |
| 3    | Server → Client | Game result (win/draw/loss)  |
| 4    | Server → Client | Error message                |

## Game Templates

| Template | Turn Timer | Description                |
|----------|------------|----------------------------|
| Classic  | None       | Pure Tic-Tac-Toe, no clock |
| Standard | 30s        | 30 seconds per move        |
| Blitz    | 10s        | 10 seconds per move        |

## Testing

```bash
# Server unit tests
cd server
go test ./internal/game/ -v
```

## License

MIT
