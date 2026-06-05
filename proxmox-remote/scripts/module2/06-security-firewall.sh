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
if [[ "$host" != isp* ]]; then
  echo "[FAIL] Unsupported nginx target host: $host"
  echo "Command: hostname"
  echo "Next hint: run module2-nginx only on ISP"
  exit 1
fi

safe_apt_install nginx openssl wget curl

mkdir -p /etc/nginx/conf.d /etc/nginx/sites-enabled.d
auth_hash="$(openssl passwd -apr1 "$BASIC_AUTH_PASS")"
printf '%s:%s\n' "$BASIC_AUTH_USER" "$auth_hash" > "$BASIC_AUTH_FILE"
chmod 644 "$BASIC_AUTH_FILE"

cat > /etc/nginx/conf.d/module2-proxy.conf <<EOFINNER
server {
    listen 80;
    server_name $WEB_DOMAIN;

    auth_basic "Module 2";
    auth_basic_user_file $BASIC_AUTH_FILE;

    location / {
        proxy_pass http://$HQ_RTR_WAN_ADDR:$DOCKER_APP_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}

server {
    listen 80;
    server_name $DOCKER_DOMAIN;

    location / {
        proxy_pass http://$BR_RTR_WAN_ADDR:$DOCKER_APP_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOFINNER
cp /etc/nginx/conf.d/module2-proxy.conf /etc/nginx/sites-enabled.d/module2-proxy.conf

if ! grep -q 'include /etc/nginx/sites-enabled.d/\*.conf;' /etc/nginx/nginx.conf; then
  awk '
    BEGIN { inserted=0 }
    /^[[:space:]]*http[[:space:]]*\{/ && inserted == 0 {
      print
      print "    include /etc/nginx/sites-enabled.d/*.conf;"
      inserted=1
      next
    }
    { print }
  ' /etc/nginx/nginx.conf > /etc/nginx/nginx.conf.tmp
  mv /etc/nginx/nginx.conf.tmp /etc/nginx/nginx.conf
fi

nginx -t
service_restart_enable nginx
ss -tulpen | grep ':80' || true
wget -S -O - --header="Host: $WEB_DOMAIN" http://127.0.0.1 2>&1 | head -n 20 || true
wget --user="$BASIC_AUTH_USER" --password="$BASIC_AUTH_PASS" -S -O - --header="Host: $WEB_DOMAIN" http://127.0.0.1 2>&1 | head -n 20 || true
wget -S -O - --header="Host: $DOCKER_DOMAIN" http://127.0.0.1 2>&1 | head -n 20 || true
echo "[OK] ISP nginx reverse proxy and basic auth configured"
