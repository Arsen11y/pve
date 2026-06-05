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

echo "Planned Module 2 Samba domain actions for BR-SRV/HQ-CLI"
echo "- Prepare Samba DC for ${DOMAIN:-au-team.irpo} / ${REALM:-AU-TEAM.IRPO}."
echo "- Create/import users named ${DOMAIN_USERS_PREFIX:-hquser}1-${DOMAIN_USERS_PREFIX:-hquser}${DOMAIN_USERS_COUNT:-5}; expected CSV on BR-SRV: ${USERS_CSV_PATH:-/opt/users.csv}."
echo "- Add domain users to group ${DOMAIN_GROUP:-hq}."
echo "- Limit sudo for ${DOMAIN_GROUP:-hq} to ${SUDO_LIMITED_COMMANDS:-cat,grep,id}."
echo "- Join HQ-CLI to the domain after prereq checks pass."
echo "- Validate users.csv schema before import; do not assume column order."
echo "Read-only local checks:"
hostname || true
id "${SSH_USER:-sshuser}" || true
if [[ -e "${USERS_CSV_PATH:-/opt/users.csv}" ]]; then
  ls -l "${USERS_CSV_PATH:-/opt/users.csv}"
else
  echo "users.csv not found at ${USERS_CSV_PATH:-/opt/users.csv}; this is expected unless running on BR-SRV after file delivery."
fi
echo "TODO: no Samba provisioning in scaffold mode."
