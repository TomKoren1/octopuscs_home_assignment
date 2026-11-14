#!/usr/bin/env bash
# Provision the stack from scratch. With APP_IMAGE set, deploy that image instead of building.
set -euo pipefail
cd "$(dirname "$0")"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

# 1. Docker
if ! command -v docker >/dev/null 2>&1; then
  log "Docker not found - installing with the official script (needs sudo)"
  curl -fsSL https://get.docker.com | sudo sh
  sudo systemctl enable --now docker
fi

DOCKER="docker"
docker info >/dev/null 2>&1 || DOCKER="sudo docker"
$DOCKER compose version >/dev/null 2>&1 || die "The Docker Compose plugin (docker compose) is required"

# 2. .env
if [ ! -f .env ]; then
  log "Creating .env from .env.example with a random database password"
  password="$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  sed "s/^MONGO_PASSWORD=.*/MONGO_PASSWORD=${password}/" .env.example > .env
  chmod 600 .env
fi
HTTP_PORT="${HTTP_PORT:-$(grep -s '^HTTP_PORT=' .env | cut -d= -f2 || true)}"
HTTP_PORT="${HTTP_PORT:-80}"
URL="http://localhost:${HTTP_PORT}"

# 3. Start. nginx resolves the replicas only at start/reload (graceful).
reload_nginx() { $DOCKER compose exec -T nginx nginx -s reload >/dev/null 2>&1 || true; }

if [ -n "${APP_IMAGE:-}" ]; then
  log "Pulling ${APP_IMAGE} and starting containers (waiting for healthchecks)"
  COMPOSE="$DOCKER compose -f docker-compose.yml -f docker-compose.deploy.yml"
  $COMPOSE pull --quiet app || die "Could not pull ${APP_IMAGE}"

  old_apps="$($COMPOSE ps -q app)"
  if [ -n "$old_apps" ]; then
    # Rolling update: start new replicas next to the old ones, then remove the old
    log "Rolling update: starting new replicas next to the old ones"
    if ! $COMPOSE up -d --no-deps --no-build --no-recreate --scale app=4 --wait app; then
      # Scaling down removes the newest (broken) replicas
      $COMPOSE up -d --no-deps --no-build --no-recreate --scale app=2 app || true
      die "New replicas did not become healthy - kept the old version"
    fi
    reload_nginx
    sleep 2
    log "Rolling update: removing the old replicas"
    $DOCKER stop $old_apps >/dev/null
    $DOCKER rm $old_apps >/dev/null
    reload_nginx
  fi
  # First boot, or nginx/mongo config changes; up-to-date containers are left alone
  $COMPOSE up -d --no-build --wait || die "Stack failed to start"
else
  log "Building images and starting containers (waiting for healthchecks)"
  $DOCKER compose up -d --build --wait --quiet-pull \
    || die "Stack failed to start. If port ${HTTP_PORT} is busy, retry with: HTTP_PORT=8080 ./provision.sh"
fi
reload_nginx

# 4. Smoke test
log "Smoke test: ${URL} must show the number of apples stored in MongoDB"
db_apples="$($DOCKER compose exec -T mongo sh -c \
  'mongosh store --quiet -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" \
     --authenticationDatabase admin --eval "db.fruits.findOne({name: \"apples\"}).qty"' \
  | tr -d '[:space:]')" || die "Could not query MongoDB"
page="$(curl -fsS "$URL")" || die "Could not fetch ${URL}"
apples="$(printf '%s' "$page" | sed -n 's/.*id="apples">\([0-9]*\)<.*/\1/p')"
[ -n "$apples" ] && [ "$apples" = "$db_apples" ] \
  || die "MongoDB has '${db_apples}' apples, but the page says '${apples}'"

printf '\n\033[1;32mOK - the page shows %s apples, matching MongoDB.\033[0m\n' "$apples"
echo "Open:      ${URL}"
echo "Topology:  ./topology.sh"
echo "Teardown:  ./teardown.sh"
