set -euo pipefail

if [[ -f /tmp/de-run/de-inventory.env ]]; then
  set -a
  # shellcheck disable=SC1091
  source /tmp/de-run/de-inventory.env
  set +a
fi
if [[ -f /tmp/de-run/scripts/lib/common.sh ]]; then
  # shellcheck disable=SC1091
  source /tmp/de-run/scripts/lib/common.sh
fi

service_restart_enable() {
  local svc
  for svc in "$@"; do
    if systemctl cat "$svc" >/dev/null 2>&1; then
      systemctl enable "$svc" || true
      systemctl restart "$svc"
      return 0
    fi
  done
  return 1
}

host="$(hostname | tr '[:upper:]' '[:lower:]')"
if [[ "$host" != br-srv* ]]; then
  echo "[FAIL] Unsupported Docker target host: $host"
  echo "Command: hostname"
  echo "Next hint: run module2-docker only on BR-SRV"
  exit 1
fi

db_tar="$ADDITIONAL_MOUNT/docker/postgresql_latest.tar"
site_tar="$ADDITIONAL_MOUNT/docker/site_latest.tar"

if ! mount_additional_iso "$db_tar" "$site_tar"; then
  echo "[FAIL] Additional.iso is not mounted"
  echo "Command: mount -o ro /dev/sr0 $ADDITIONAL_MOUNT"
  echo "Next hint: attach Additional.iso to BR-SRV CD-ROM and rerun module2-docker"
  lsblk || true
  ls -la "$ADDITIONAL_MOUNT" 2>/dev/null || true
  exit 1
fi

if safe_apt_install docker; then
  echo "[OK] docker package install attempted"
elif safe_apt_install docker-engine; then
  echo "[OK] docker-engine package install attempted"
else
  echo "[FAIL] Docker package installation failed"
  echo "Command: apt-get install -y docker || apt-get install -y docker-engine"
  echo "Next hint: check ALT repositories from BR-SRV"
  exit 1
fi

service_restart_enable docker docker.service

docker load -i "$db_tar"
docker load -i "$site_tar"

docker network inspect "$DOCKER_NETWORK" >/dev/null 2>&1 || docker network create "$DOCKER_NETWORK"
docker rm -f "$DOCKER_APP_CONTAINER" "$DOCKER_DB_CONTAINER" >/dev/null 2>&1 || true

docker run -d \
  --name "$DOCKER_DB_CONTAINER" \
  --network "$DOCKER_NETWORK" \
  --restart unless-stopped \
  -e POSTGRES_DB="$DOCKER_DB_NAME" \
  -e POSTGRES_USER="$DOCKER_DB_USER" \
  -e POSTGRES_PASSWORD="$DOCKER_DB_PASS" \
  "$DOCKER_DB_IMAGE"

docker run -d \
  --name "$DOCKER_APP_CONTAINER" \
  --network "$DOCKER_NETWORK" \
  --restart unless-stopped \
  -p "$DOCKER_APP_PORT:8000" \
  -e DB_TYPE=postgres \
  -e DB_HOST="$DOCKER_DB_CONTAINER" \
  -e DB_NAME="$DOCKER_DB_NAME" \
  -e DB_PORT=5432 \
  -e DB_USER="$DOCKER_DB_USER" \
  -e DB_PASS="$DOCKER_DB_PASS" \
  "$DOCKER_APP_IMAGE"

docker ps
ss -tulpen | grep "$DOCKER_APP_PORT" || true
curl -fsSL "http://127.0.0.1:$DOCKER_APP_PORT" | head -n 20 || true
echo "[OK] Docker app configured on BR-SRV port $DOCKER_APP_PORT"
