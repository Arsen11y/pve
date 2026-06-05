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

mount_additional_iso() {
  mkdir -p "$ADDITIONAL_MOUNT"
  if findmnt -n "$ADDITIONAL_MOUNT" >/dev/null 2>&1; then
    return 0
  fi
  if [[ -b "$ADDITIONAL_CDROM_1" ]]; then
    mount -o ro "$ADDITIONAL_CDROM_1" "$ADDITIONAL_MOUNT" || true
  fi
  if ! findmnt -n "$ADDITIONAL_MOUNT" >/dev/null 2>&1 && [[ -b "$ADDITIONAL_CDROM_2" ]]; then
    mount -o ro "$ADDITIONAL_CDROM_2" "$ADDITIONAL_MOUNT" || true
  fi
  findmnt -n "$ADDITIONAL_MOUNT" >/dev/null 2>&1
}

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
if [[ "$host" != hq-srv* ]]; then
  echo "[FAIL] Unsupported web target host: $host"
  echo "Command: hostname"
  echo "Next hint: run module2-web only on HQ-SRV"
  exit 1
fi

if ! mount_additional_iso; then
  echo "[FAIL] Additional.iso is not mounted"
  echo "Command: mount -o ro /dev/sr0 $ADDITIONAL_MOUNT"
  echo "Next hint: attach Additional.iso to HQ-SRV CD-ROM and rerun module2-web"
  exit 1
fi

test -f "$ADDITIONAL_MOUNT/web/dump.sql"
test -f "$ADDITIONAL_MOUNT/web/index.php"
test -f "$ADDITIONAL_MOUNT/web/logo.png"

safe_apt_install apache2 apache2-mod_php8.0 php8.0 php8.0-mysqli mariadb-server mariadb-client

service_restart_enable mariadb mysqld
service_restart_enable "$WEB_HTTP_SERVICE" apache2 httpd

mysql -uroot <<EOFINNER
CREATE DATABASE IF NOT EXISTS $WEB_DB_NAME DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$WEB_DB_USER'@'localhost' IDENTIFIED BY '$WEB_DB_PASS';
ALTER USER '$WEB_DB_USER'@'localhost' IDENTIFIED BY '$WEB_DB_PASS';
GRANT ALL PRIVILEGES ON $WEB_DB_NAME.* TO '$WEB_DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOFINNER

mysql -uroot "$WEB_DB_NAME" < "$ADDITIONAL_MOUNT/web/dump.sql"

mkdir -p "$WEB_DOCROOT"
cp "$ADDITIONAL_MOUNT/web/index.php" "$WEB_DOCROOT/index.php"
cp "$ADDITIONAL_MOUNT/web/logo.png" "$WEB_DOCROOT/logo.png"
if [[ -f "$WEB_DOCROOT/index.html" && ! -f "$WEB_DOCROOT/index.html.bak" ]]; then
  mv "$WEB_DOCROOT/index.html" "$WEB_DOCROOT/index.html.bak"
elif [[ -f "$WEB_DOCROOT/index.html" ]]; then
  mv "$WEB_DOCROOT/index.html" "$WEB_DOCROOT/index.html.bak.$(date +%Y%m%d%H%M%S)"
fi

sed -i \
  -e "s/\(['\"]\)user\1/\1$WEB_DB_USER\1/g" \
  -e "s/\(['\"]\)db\1/\1$WEB_DB_NAME\1/g" \
  -e "s/\(['\"]\)password\1/\1$WEB_DB_PASS\1/g" \
  -e "s/\(['\"]\)P@ssw0rd\1/\1$WEB_DB_PASS\1/g" \
  "$WEB_DOCROOT/index.php"

chown -R root:root "$WEB_DOCROOT" 2>/dev/null || true
service_restart_enable "$WEB_HTTP_SERVICE" apache2 httpd

ss -tulpen | grep ':80' || true
curl -fsSL -D - http://127.0.0.1 -o /tmp/module2-web-check.html || true
head -n 20 /tmp/module2-web-check.html 2>/dev/null || true
echo "[OK] HQ-SRV web service configured"
