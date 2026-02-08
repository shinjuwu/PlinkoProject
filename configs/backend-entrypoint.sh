#!/bin/sh
set -e

echo "[entrypoint] Starting backend (first run - migrations)..."

# Run backend once to execute DB migrations.
# It will crash after migrations because server_info has wrong notification URL.
# We use timeout + || true to gracefully handle the expected crash.
timeout 30 ./dcc_backend || true

echo "[entrypoint] First run finished (crash expected). Fixing server_info notification URL..."

# Update server_info to point notification to the gamehub Docker service
PGPASSWORD="${DB_PASSWORD:-localtest}" psql \
  -h "${DB_HOST:-admin-postgres}" \
  -U "${DB_USER:-postgres}" \
  -d "${DB_NAME:-dcc_game}" \
  -c "UPDATE server_info SET addresses = jsonb_set(addresses, '{notification}', '\"http://gamehub:9643/\"'), ip = 'gamehub' WHERE code = 'dev';" \
  2>&1 || echo "[entrypoint] WARNING: Failed to update server_info (table may not exist yet)"

echo "[entrypoint] server_info updated. Starting backend for real..."

# Start backend for real - this time gameKillInfo init should succeed
exec ./dcc_backend
