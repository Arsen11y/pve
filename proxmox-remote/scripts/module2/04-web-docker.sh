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
echo "- BR-SRV Docker app from images ${DOCKER_IMAGE_APP:-site_latest} and ${DOCKER_IMAGE_DB:-postgresql_latest}."
echo "- Containers ${DOCKER_APP_CONTAINER:-site}/${DOCKER_DB_CONTAINER:-db}, DB ${DOCKER_DB_NAME:-testdb3}, user ${DOCKER_DB_USER:-test3c}, password from DOCKER_DB_PASS, external port ${DOCKER_APP_PORT:-8083}."
echo "- HQ-SRV Apache + MariaDB, database ${WEB_DB_NAME:-webdb}, user ${WEB_DB_USER:-web3}, password from WEB_DB_PASS."
echo "- Import dump.sql and copy index.php/images only after source paths are confirmed."
echo "- Publish ${WEB_DOMAIN:-web.au-team.irpo} and ${DOCKER_DOMAIN:-docker.au-team.irpo} only after reverse proxy step."
echo "Read-only local checks:"
ss -tulpen | grep -E ":(${DOCKER_APP_PORT:-8083}|80|443)" || true
command -v docker || true
echo "TODO: no Docker, Apache, or MariaDB changes in scaffold mode."
