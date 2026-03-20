#!/usr/bin/env bash
# deploy.sh — Build and deploy Tic-Tac-Toe (Nakama + Flutter web)
#
# Usage:
#   ./deploy/deploy.sh                    # local deployment (localhost)
#   DOMAIN=play.example.com ./deploy.sh   # production with custom domain
#
# Prerequisites:
#   - Docker & Docker Compose
#   - Flutter SDK (for web build)

set -euo pipefail
cd "$(dirname "$0")/.."

DOMAIN="${DOMAIN:-localhost}"
NAKAMA_SSL="${NAKAMA_SSL:-false}"
NAKAMA_HOST="${DOMAIN}"

echo "=== Tic-Tac-Toe Deploy ==="
echo "Domain: ${DOMAIN}"
echo ""

# Step 1: Build Go plugin (Linux ELF via Docker)
echo "[1/4] Building Go plugin..."
docker build -f deploy/Dockerfile.nakama -t ttt-nakama ./server
echo "  Done."

# Step 2: Build Flutter web
echo "[2/4] Building Flutter web..."
cd client
flutter pub get
flutter build web --release \
  --dart-define=NAKAMA_HOST="${NAKAMA_HOST}" \
  --dart-define=NAKAMA_HTTP_PORT=80 \
  --dart-define=NAKAMA_SSL="${NAKAMA_SSL}"
cd ..
echo "  Done."

# Step 3: Start services
echo "[3/4] Starting services..."
docker compose -f deploy/docker-compose.prod.yml up -d
echo "  Done."

# Step 4: Health check
echo "[4/4] Waiting for Nakama..."
for i in $(seq 1 30); do
  if curl -sf "http://localhost:7350/healthcheck" > /dev/null 2>&1; then
    echo "  Nakama is healthy!"
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "  WARNING: Nakama health check timed out. Check logs: docker logs ttt-nakama"
  fi
  sleep 2
done

echo ""
echo "=== Deployment Complete ==="
if [ "${DOMAIN}" = "localhost" ]; then
  echo "  Web:    http://localhost"
  echo "  Nakama: http://localhost:7350"
else
  echo "  Web:    http://${DOMAIN}"
fi
echo ""
echo "Useful commands:"
echo "  docker logs -f ttt-nakama     # Nakama logs"
echo "  docker logs -f ttt-web        # Nginx logs"
echo "  docker compose -f deploy/docker-compose.prod.yml down  # Stop all"
