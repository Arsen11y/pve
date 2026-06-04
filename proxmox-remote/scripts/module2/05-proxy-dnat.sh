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

echo "Planned Module 2 proxy/DNAT actions"
echo "- Configure HQ-RTR/BR-RTR DNAT for ${APP_PORT:-8080} and SSH 2026."
echo "- Configure ISP nginx reverse proxy for web.${DOMAIN:-au-team.irpo} and docker.${DOMAIN:-au-team.irpo}."
echo "- Protect web.${DOMAIN:-au-team.irpo} with basic auth user ${WEB_AUTH_USER:-WEBc}."
echo "Read-only local checks:"
nft list ruleset || true
ss -tulpen | grep -E ":(${APP_PORT:-8080}|2026|80|443)" || true
echo "TODO: no nftables or nginx changes in scaffold mode."
