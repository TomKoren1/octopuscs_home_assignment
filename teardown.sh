#!/usr/bin/env bash
# Remove everything provision.sh created: containers, networks, the data
# volume and the locally built app image. Add --keep-data to keep the volume.
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
