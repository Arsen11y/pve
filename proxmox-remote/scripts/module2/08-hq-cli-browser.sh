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

host="$(hostname | tr '[:upper:]' '[:lower:]')"
if [[ "$host" != hq-cli* ]]; then
  echo "[FAIL] Unsupported browser target host: $host"
  echo "Command: hostname"
  echo "Next hint: run module2-browser only on HQ-CLI"
  exit 1
fi

safe_apt_install "$YANDEX_BROWSER_PREINSTALL_PACKAGE" "$YANDEX_BROWSER_PACKAGE"

rpm -qa | grep "$YANDEX_BROWSER_PACKAGE"
test -x "$YANDEX_BROWSER_BIN"
test -f /usr/share/applications/yandex-browser.desktop
"$YANDEX_BROWSER_BIN" --version | grep -i Yandex
echo "[OK] Yandex Browser installed on HQ-CLI"
