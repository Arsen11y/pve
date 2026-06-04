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
echo "- Create ${HQ_USERS_COUNT:-5} users with prefix ${HQ_USERS_PREFIX:-hquser} in group ${HQ_GROUP:-hq}."
echo "- Limit sudo for ${HQ_GROUP:-hq} to ${SUDO_LIMITED_COMMANDS:-cat,grep,id}."
echo "- Join HQ-CLI to the domain after prereq checks pass."
echo "- Import users.csv only after file path and schema are confirmed."
echo "Read-only local checks:"
hostname || true
id "${SSH_USER:-sshuser}" || true
echo "TODO: no Samba provisioning in scaffold mode."
