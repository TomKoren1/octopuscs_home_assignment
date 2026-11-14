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
# nginx looks up the app replicas' addresses when it starts or reloads.
# Whenever replicas may have been replaced, reload it: gracefully, so no
# request is dropped. This also applies changes to nginx/default.conf.
reload_nginx() { $DOCKER compose exec -T nginx nginx -s reload >/dev/null 2>&1 || true; }

if [ -n "${APP_IMAGE:-}" ]; then
  # Deploy mode (used by CD): run a pre-built image from a registry.
  log "Pulling ${APP_IMAGE} and starting containers (waiting for healthchecks)"
  COMPOSE="$DOCKER compose -f docker-compose.yml -f docker-compose.deploy.yml"
  $COMPOSE pull --quiet app || die "Could not pull ${APP_IMAGE}"

  old_apps="$($COMPOSE ps -q app)"
  if [ -n "$old_apps" ]; then
    # Rolling update: nginx always has a healthy replica to send requests to.
    # 1. Start new replicas NEXT TO the old ones and wait until healthy.
    #    (--no-recreate keeps the old containers; the new ones get the new image)
    log "Rolling update: starting new replicas next to the old ones"
    if ! $COMPOSE up -d --no-deps --no-build --no-recreate --scale app=4 --wait app; then
      # Roll back: scaling down removes the newest containers (the broken ones)
      $COMPOSE up -d --no-deps --no-build --no-recreate --scale app=2 app || true
      die "New replicas did not become healthy - kept the old version"
    fi
    # 2. Tell nginx about the new replicas.
    reload_nginx
    sleep 2
    # 3. Remove the old replicas. `docker stop` sends SIGTERM, so each one
    #    finishes its in-flight requests; nginx retries anything refused.
    log "Rolling update: removing the old replicas"
    $DOCKER stop $old_apps >/dev/null
    $DOCKER rm $old_apps >/dev/null
    # 4. Tell nginx the old replicas are gone.
    reload_nginx
  fi
  # Start anything not running yet (first boot), and apply config changes to
  # nginx/mongo if there are any. Already up-to-date containers are left alone.
  $COMPOSE up -d --no-build --wait || die "Stack failed to start"
else
  # Default mode: build the app image from source.
  log "Building images and starting containers (waiting for healthchecks)"
  $DOCKER compose up -d --build --wait --quiet-pull \
    || die "Stack failed to start. If port ${HTTP_PORT} is busy, retry with: HTTP_PORT=8080 ./provision.sh"
fi
reload_nginx

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
