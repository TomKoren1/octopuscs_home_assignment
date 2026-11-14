#!/usr/bin/env bash
# Provision the whole architecture from scratch on a Linux host:
#   1. install Docker if it is missing
#   2. create .env (with a random DB password) if it is missing
#   3. build + start all containers and wait until they are healthy
#      (or, if APP_IMAGE is set, pull that pre-built image instead of building)
#   4. smoke-test: the page must show the apple count stored in MongoDB
set -euo pipefail
cd "$(dirname "$0")"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

# --- 1. Docker -------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  log "Docker not found - installing with the official script (needs sudo)"
  curl -fsSL https://get.docker.com | sudo sh
  sudo systemctl enable --now docker
fi

# Use sudo only if this user cannot talk to the Docker daemon directly
DOCKER="docker"
docker info >/dev/null 2>&1 || DOCKER="sudo docker"
$DOCKER compose version >/dev/null 2>&1 || die "The Docker Compose plugin (docker compose) is required"

# --- 2. .env ---------------------------------------------------------------
if [ ! -f .env ]; then
  log "Creating .env from .env.example with a random database password"
  password="$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  sed "s/^MONGO_PASSWORD=.*/MONGO_PASSWORD=${password}/" .env.example > .env
  chmod 600 .env
fi
HTTP_PORT="${HTTP_PORT:-$(grep -s '^HTTP_PORT=' .env | cut -d= -f2 || true)}"
HTTP_PORT="${HTTP_PORT:-80}"
URL="http://localhost:${HTTP_PORT}"

# --- 3. Build (or pull) + start ---------------------------------------------
if [ -n "${APP_IMAGE:-}" ]; then
  # Deploy mode (used by CD): run a pre-built image from a registry.
  log "Pulling ${APP_IMAGE} and starting containers (waiting for healthchecks)"
  COMPOSE="$DOCKER compose -f docker-compose.yml -f docker-compose.deploy.yml"
  $COMPOSE pull --quiet app || die "Could not pull ${APP_IMAGE}"
  $COMPOSE up -d --no-build --wait || die "Stack failed to start"
else
  # Default mode: build the app image from source.
  log "Building images and starting containers (waiting for healthchecks)"
  $DOCKER compose up -d --build --wait --quiet-pull \
    || die "Stack failed to start. If port ${HTTP_PORT} is busy, retry with: HTTP_PORT=8080 ./provision.sh"
fi

# --- 4. Smoke test ---------------------------------------------------------
# The requirement: "the html page returns the number of apples in the DB".
# So: read the number straight from MongoDB, then check the page shows the same.
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
