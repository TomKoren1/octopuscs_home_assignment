#!/usr/bin/env bash
# Remove everything provision.sh created. --keep-data keeps the DB volume.
set -euo pipefail
cd "$(dirname "$0")"

DOCKER="docker"
docker info >/dev/null 2>&1 || DOCKER="sudo docker"

if [ "${1:-}" = "--keep-data" ]; then
  $DOCKER compose down --remove-orphans --rmi local
else
  $DOCKER compose down --remove-orphans --rmi local --volumes
fi
echo "Done."
