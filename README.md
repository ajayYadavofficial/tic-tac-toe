# Multiplayer Tic-Tac-Toe

Real-time multiplayer Tic-Tac-Toe built with **Nakama** (game server), **Go** (server-side game logic), and **Flutter** (cross-platform client).

## Live Demo

| Resource | URL |
|----------|-----|
| Game (Web) | http://3.110.48.57 |
| Nakama Server | http://3.110.48.57/v2 (proxied via nginx) |
| Source Code | https://github.com/ajayYadavofficial/tic-tac-toe |

> The game is deployed on AWS EC2 (ap-south-1, Mumbai). Open two browser tabs to play against yourself, or share the link with a friend.

## Architecture and Design Decisions

```
  Browser ──► :80 (nginx / ttt-web)
                ├── /          → Flutter web app (static files)
                ├── /v2/*      → Nakama HTTP API (reverse-proxied to ttt-nakama:7350)
                └── /ws        → Nakama WebSocket  (reverse-proxied to ttt-nakama:7350)

  ttt-web      (nginx:alpine)      ── port 80 exposed to internet
  ttt-nakama   (nakama:3.22.0)     ── port 7350 internal only
  ttt-postgres (postgres:15-alpine)── port 5432 internal only
```

### Why Nakama?
Nakama provides built-in support for authoritative multiplayer matches, matchmaking, leaderboards, user accounts, and real-time WebSocket communication. Instead of building these from scratch, we use Nakama as the infrastructure layer and write game-specific logic as a **Go runtime plugin**.

### Why Server-Authoritative?
The server owns all game state. The client only sends a move request (cell position 0-8); the server validates it (correct turn, valid cell, game not over) before applying it and broadcasting the updated state. This prevents any form of client-side cheating.

### Why Go Plugin (not Lua/TypeScript)?
Go plugins compile to native code and run inside the Nakama process with zero overhead. For a game server where tick-rate matters, Go provides the best performance. It also gives us full type safety and access to Go's standard library.

### Why Flutter?
Flutter compiles to web, Android, and iOS from a single codebase. For this assignment we deploy the web build, but the same code can produce a mobile APK with no changes.

### Design Choices

- **Device-based authentication** — No passwords or emails. Each device gets a UUID on first launch, stored in SharedPreferences. Returning users are auto-authenticated. Usernames are unique display names (not login credentials).
- **Template-based matchmaking** — Game modes (Classic, Blitz) are defined as server-side templates. The matchmaker query includes `templateId`, so players only match with others who picked the same mode.
- **Optimistic concurrency for stats** — Player stats (wins/losses/draws/score) are read-modify-written with version checks to handle concurrent match endings safely.
- **Nginx reverse proxy** — A single port 80 serves both the Flutter web app and proxies Nakama API/WebSocket traffic. This simplifies deployment (no CORS, no extra ports).

## Features

- **Server-authoritative game logic** — all moves validated server-side, state managed on server
- **Automatic matchmaking** — players pick a game mode, Nakama pairs them in ~1 second
- **Multiple game modes** — Classic (no timer), Standard (30s/turn), Blitz (10s/turn)
- **Turn timer with auto-forfeit** — server enforces time limits, auto-forfeits on timeout
- **Concurrent game support** — multiple isolated game sessions run simultaneously
- **Leaderboard & player stats** — wins/losses/draws/score tracked and persisted in PostgreSQL
- **Real-time WebSocket** — instant move updates, state broadcasts every server tick
- **Device-based auth** — no passwords, automatic session restore on return visits
- **Auto-reconnect** — exponential backoff on WebSocket disconnect (up to 6 retries)
- **Modern UI** — gradient avatars, staggered animations, responsive layout

## Tech Stack

| Layer    | Technology                      |
|----------|---------------------------------|
| Backend  | Go 1.22 (Nakama runtime plugin) |
| Server   | Nakama 3.22.0                   |
| Database | PostgreSQL 15                   |
| Frontend | Flutter 3.x (Dart)              |
| Proxy    | nginx (alpine)                  |
| Infra    | Docker Compose, AWS EC2         |


## Setup and Installation

### Prerequisites

- [Docker](https://docs.docker.com/get-docker/) & Docker Compose
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.x+)
- [Go 1.22+](https://go.dev/dl/) (only needed if modifying server code)

### Local Development

#### 1. Start Nakama + PostgreSQL

```bash
# Build the Go plugin for Linux (required for Docker)
docker run --rm \
  -v "$PWD/server":/backend \
  -w /backend \
  heroiclabs/nakama-pluginbuilder:3.22.0 \
  build -buildmode=plugin -trimpath -o /backend/modules/tictactoe.so .

# Start Nakama + PostgreSQL
docker compose up -d
```

Nakama console: http://localhost:7351 (admin / password)

#### 2. Run the Flutter Client

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

#### 3. Run Server Tests

```bash
cd server
go test ./internal/game/ -v
```

## Deployment Process

The production deployment uses Docker Compose with three containers, all on a single EC2 instance.

### Current Deployment

- **Cloud Provider:** AWS EC2 (ap-south-1, Mumbai)
- **Instance Type:** c7i-flex.large (2 vCPU, 4GB RAM)
- **OS:** Amazon Linux 2023

### Step-by-Step Deployment

```bash
# 1. SSH into the server
ssh -i ~/.ssh/ttt-key.pem ec2-user@<PUBLIC_IP>

# 2. Clone the repository
git clone https://github.com/ajayYadavofficial/tic-tac-toe.git
cd tic-tac-toe

# 3. Build the Nakama image (compiles Go plugin inside Docker)
docker build -f deploy/Dockerfile.nakama -t ttt-nakama server/

# 4. Build the Flutter web image (bake in server IP)
docker build -f deploy/Dockerfile.web -t ttt-web \
  --build-arg NAKAMA_HOST=<PUBLIC_IP> \
  --build-arg NAKAMA_PORT=80 \
  --build-arg NAKAMA_SSL=false .

# 5. Start all services
docker compose -f deploy/docker-compose.prod.yml up -d

# 6. Verify
docker ps   # Should show ttt-postgres (healthy), ttt-nakama (healthy), ttt-web (up)
```

The game is accessible at `http://<PUBLIC_IP>`.

### Updating After Code Changes

```bash
cd ~/tic-tac-toe
git pull
docker build -f deploy/Dockerfile.nakama -t ttt-nakama server/
docker build -f deploy/Dockerfile.web -t ttt-web \
  --build-arg NAKAMA_HOST=<PUBLIC_IP> \
  --build-arg NAKAMA_PORT=80 \
  --build-arg NAKAMA_SSL=false .
docker compose -f deploy/docker-compose.prod.yml up -d
```

## API / Server Configuration

### Server RPCs

All RPCs require an authenticated session. Called via Nakama's HTTP API (`POST /v2/rpc/<id>`).

| RPC                | Payload                          | Response                                      |
|--------------------|----------------------------------|-----------------------------------------------|
| `create_match`     | `""`                             | `{"match_id": "uuid"}`                        |
| `list_matches`     | `""`                             | `{"matches": [{"match_id": "uuid"}, ...]}`    |
| `list_templates`   | `""`                             | `{"templates": [{"id":1, "name":"Classic", "variant":"classic", "turn_seconds":0}, ...]}` |
| `update_username`  | `{"username": "player1"}`        | `""`                                          |
| `release_username` | `""`                             | `""`                                          |
| `player_stats`     | `""`                             | `{"wins":5, "losses":2, "draws":1, "score":600}` |
| `get_leaderboard`  | `""`                             | `{"records": [{"username":"player1", "score":600, "wins":5, "losses":2, "draws":1}, ...]}` |

### WebSocket OpCodes

Communication between client and server during a match uses Nakama's match data messages with these opcodes:

| OpCode | Direction       | Payload                                      | Description                     |
|--------|-----------------|----------------------------------------------|---------------------------------|
| 1      | Client → Server | `{"position": 4}`                            | Player makes a move             |
| 3      | Server → Client | `{"board":["","X","","","O",...], "turn":"uuid", "playerX":"uuid", ...}` | Game state update |
| 4      | Server → Client | `{"result":"win", "winner":"uuid", "board":[...], ...}` | Game over result |
| 5      | Client → Server | `{}`                                         | Player resigns                  |
| 6      | Server → Client | `{"message": "Not your turn"}`               | Error message                   |

### Game Templates

| ID | Name     | Variant    | Turn Timer | Description                |
|----|----------|------------|------------|----------------------------|
| 1  | Classic  | `classic`  | None       | Pure Tic-Tac-Toe, no clock |
| 2  | Blitz    | `blitz`    | 10s        | Fast-paced, 10s per move   |


### Server Configuration

Nakama is configured via command-line flags in `docker-compose.prod.yml`:

| Parameter                  | Value  | Description                        |
|----------------------------|--------|------------------------------------|
| `logger.level`             | INFO   | Log verbosity                      |
| `session.token_expiry_sec` | 7200   | Session token TTL (2 hours)        |
| `runtime.path`             | /nakama/data/modules | Go plugin directory    |
| `matchmaker.interval_sec`  | 1      | Matchmaker tick interval (1 second)|

Client configuration is baked in at build time via `--dart-define` flags:

| Flag               | Default     | Description              |
|--------------------|-------------|--------------------------|
| `NAKAMA_HOST`      | `localhost` | Nakama server hostname   |
| `NAKAMA_HTTP_PORT` | `7350`      | Nakama HTTP/WS port      |
| `NAKAMA_SSL`       | `false`     | Use HTTPS/WSS            |

## How to Test Multiplayer

### Quick Test (Live Server)

1. Open **http://3.110.48.57** in two separate browser tabs (or two different devices)
2. In each tab, enter a unique nickname and tap **Continue**
3. In both tabs, tap **Play** on the same game mode (e.g., "Classic")
4. The matchmaker pairs them within ~1 second — the game board appears
5. Take turns tapping cells — moves appear in real-time on both screens
6. When someone wins (or it's a draw), the result screen shows with points
7. Check the **Leaderboard** section in the lobby to see updated rankings


### Local Testing

```bash
# Run server unit tests
cd server
go test ./internal/game/ -v

# Start local server
docker compose up -d

# Run Flutter client
cd client && flutter run -d chrome

# Open a second Chrome window for the opponent
# (use a different Chrome profile or incognito to get a separate device ID)
```

## License

MIT
