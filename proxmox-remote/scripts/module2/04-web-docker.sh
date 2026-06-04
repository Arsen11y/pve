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
echo "- BR-SRV Docker Compose file ${WIKI_COMPOSE_FILE:-wiki.yml} with services ${WIKI_SERVICE:-wiki} and ${WIKI_DB_SERVICE:-mariadb}."
echo "- MediaWiki database ${APP_DB_NAME:-mediawiki}, user ${APP_DB_USER:-wiki}, password from APP_DB_PASS, external port ${APP_PORT:-8080}."
echo "- HQ-SRV Moodle with Apache + MariaDB, database ${MOODLE_DB_NAME:-moodledb}, user ${MOODLE_DB_USER:-moodle}, admin password from MOODLE_ADMIN_PASS."
echo "- Publish ${WIKI_DOMAIN:-wiki.au-team.irpo} and ${MOODLE_DOMAIN:-moodle.au-team.irpo} only after reverse proxy step."
echo "Read-only local checks:"
ss -tulpen | grep -E ":(${APP_PORT:-8080}|80|443)" || true
command -v docker || true
echo "TODO: no Docker, MediaWiki, Moodle, Apache, or MariaDB changes in scaffold mode."
