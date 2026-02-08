#!/usr/bin/env bash
set -euo pipefail

COMPOSE_FILE="docker-compose.local.yml"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ─── Pre-flight checks ───

if ! command -v docker &>/dev/null; then
  error "Docker is not installed or not in PATH."
  exit 1
fi

if ! docker info &>/dev/null; then
  error "Docker daemon is not running. Please start Docker first."
  exit 1
fi

if ! command -v docker compose &>/dev/null && ! docker compose version &>/dev/null 2>&1; then
  error "Docker Compose (v2) is not available."
  exit 1
fi

# ─── Build ───

info "Building all images..."
docker compose -f "$COMPOSE_FILE" build

# ─── Start ───

info "Starting all services..."
docker compose -f "$COMPOSE_FILE" up -d

# ─── Wait for health checks ───

wait_for_healthy() {
  local container="$1"
  local max_wait="${2:-120}"
  local elapsed=0

  printf "  Waiting for %-20s " "$container..."
  while [ $elapsed -lt $max_wait ]; do
    status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "missing")
    if [ "$status" = "healthy" ]; then
      echo -e "${GREEN}healthy${NC}"
      return 0
    fi
    sleep 3
    elapsed=$((elapsed + 3))
  done
  echo -e "${RED}timeout (${max_wait}s)${NC}"
  return 1
}

wait_for_http() {
  local url="$1"
  local label="$2"
  local max_wait="${3:-90}"
  local elapsed=0

  printf "  Waiting for %-20s " "$label..."
  while [ $elapsed -lt $max_wait ]; do
    if curl -sf "$url" >/dev/null 2>&1; then
      echo -e "${GREEN}ready${NC}"
      return 0
    fi
    sleep 3
    elapsed=$((elapsed + 3))
  done
  echo -e "${RED}timeout (${max_wait}s)${NC}"
  return 1
}

# Like wait_for_http but accepts any HTTP response (including 404)
# Used for services that have no root "/" route
wait_for_http_any() {
  local url="$1"
  local label="$2"
  local max_wait="${3:-90}"
  local elapsed=0

  printf "  Waiting for %-20s " "$label..."
  while [ $elapsed -lt $max_wait ]; do
    if curl -so /dev/null "$url" 2>/dev/null; then
      echo -e "${GREEN}ready${NC}"
      return 0
    fi
    sleep 3
    elapsed=$((elapsed + 3))
  done
  echo -e "${RED}timeout (${max_wait}s)${NC}"
  return 1
}

info "Waiting for infrastructure services..."
wait_for_healthy admin-postgres
wait_for_healthy admin-redis
wait_for_healthy game-postgres
wait_for_healthy game-redis
wait_for_healthy dcctools-mysql

info "Waiting for application services..."
wait_for_http "http://localhost:9986/api/v1/health/health" "backend"
wait_for_http_any "http://localhost:9988/" "orderservice" || warn "OrderService may not be ready"
wait_for_http_any "http://localhost:8896/" "chatservice" || warn "ChatService may not be ready"
wait_for_http_any "http://localhost:17782/" "monitorservice" || warn "MonitorService may not be ready"
wait_for_http "http://localhost:80/manager" "frontend"
wait_for_http "http://localhost:9643/ping" "gamehub" || warn "GameHub may not be available"
wait_for_http "http://localhost:8080/" "plinko" || warn "Plinko game client may not be available"
wait_for_http "http://localhost:8082/" "dcctools" || warn "DCC Tools may not be available"

# ─── Summary ───

echo ""
info "============================================"
info "  Local Integration Test Environment Ready"
info "============================================"
echo ""
echo "  Backend API:     http://localhost:9986/api/v1/health/health"
echo "  OrderService:    http://localhost:9988/"
echo "  ChatService:     http://localhost:8896/"
echo "  MonitorService:  http://localhost:17782/"
echo "  Admin Panel:     http://localhost/manager"
echo "  GameHub:         http://localhost:9643/ping"
echo "  Plinko Client:   http://localhost:8080/"
echo "  DCC Tools:       http://localhost:8082/"
echo ""
echo "  Admin DB:        localhost:5432  (dcc_game / postgres / localtest)"
echo "  Game DB:         localhost:5433  (dayon_demo / postgres / localtest)"
echo "  Order DB:        localhost:5432  (dcc_order / postgres / localtest)"
echo "  Chat DB:         localhost:5432  (dcc_chat / postgres / localtest)"
echo "  Monitor DB:      localhost:5432  (monitor / postgres / localtest)"
echo "  DCC Tools MySQL: localhost:3307  (dcc / dccuser / Dcc@12345)"
echo "  Admin Redis:     localhost:6379  (password: localtest)"
echo "  Game Redis:      localhost:6380  (password: localtest)"
echo ""
info "To stop:  docker compose -f $COMPOSE_FILE down"
info "To reset: docker compose -f $COMPOSE_FILE down -v"
