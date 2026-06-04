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

echo "Planned Module 2 web/Docker actions"
echo "- BR-SRV Docker app testapp + db on port ${APP_PORT:-8080}, app DB ${APP_DB_NAME:-appdb}."
echo "- HQ-SRV Apache + MariaDB, database ${WEB_DB_NAME:-webdb}, user ${WEB_DB_USER:-webc}."
echo "- Prepare index.php and image assets from inventory-defined sources."
echo "Read-only local checks:"
ss -tulpen | grep -E ":(${APP_PORT:-8080}|80|443)" || true
command -v docker || true
echo "TODO: no Docker, Apache, or MariaDB changes in scaffold mode."
