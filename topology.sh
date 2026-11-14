#!/usr/bin/env bash
# Show the running architecture, read live from Docker.
set -euo pipefail
cd "$(dirname "$0")"

DOCKER="docker"
docker info >/dev/null 2>&1 || DOCKER="sudo docker"

title() { printf '\n\033[1;34m=== %s ===\033[0m\n' "$*"; }

ids="$($DOCKER compose ps -q)"
[ -n "$ids" ] || { echo "Nothing is running. Run ./provision.sh first."; exit 1; }
project="$($DOCKER inspect --format '{{index .Config.Labels "com.docker.compose.project"}}' $ids | head -1)"
port="$($DOCKER compose port nginx 80 | sed 's/.*://')"

title "Containers"
$DOCKER compose ps --format 'table {{.Name}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'

title "Networks (who can talk to whom)"
for net in $($DOCKER network ls -q --filter "label=com.docker.compose.project=${project}"); do
  $DOCKER network inspect "$net" --format \
'{{.Name}}  subnet {{range .IPAM.Config}}{{.Subnet}}{{end}}
{{range .Containers}}    {{printf "%-28s" .Name}} {{.IPv4Address}}
{{end}}'
done

title "Volumes (persistent data)"
$DOCKER volume ls --filter "label=com.docker.compose.project=${project}" --format '{{.Name}}  ({{.Driver}})'

title "Diagram"
cat <<DIAGRAM
        Browser
           |  http://localhost:${port}   (the only published port)
     +-----v------+
     |   nginx    |  load balancer / reverse proxy
     +--+------+--+
        |      |          network: ${project}_frontend
   +----v--+ +-v-----+
   | app 1 | | app 2 |    Node.js + Express (replicas)
   +----+--+ +-+-----+
        |      |          network: ${project}_backend
     +--v------v--+
     |  MongoDB   |---> volume ${project}_mongo-data
     +------------+
DIAGRAM

title "Load balancer in action (4 requests)"
for i in 1 2 3 4; do
  curl -fsS "http://localhost:${port}" \
    | sed -n -e 's/.*id="apples">\([0-9]*\)<.*/apples=\1/p' -e 's/.*Served by container: \([0-9a-f]*\).*/served-by=\1/p' \
    | paste -sd' ' | sed "s/^/  request $i: /"
done
