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
echo "- Configure HQ-RTR DNAT port ${DNAT_PORT:-2024} to ${DNAT_HQ_TARGET:-192.168.100.2:2024}."
echo "- Configure BR-RTR DNAT port ${DNAT_PORT:-2024} to ${DNAT_BR_TARGET:-192.168.10.2:2024}."
echo "- Configure nginx reverse proxy on ${REVERSE_PROXY_HOST:-hq-rtr.au-team.irpo}."
echo "- Proxy ${MOODLE_DOMAIN:-moodle.au-team.irpo} to HQ-SRV Moodle."
echo "- Proxy ${WIKI_DOMAIN:-wiki.au-team.irpo} to BR-SRV MediaWiki on port ${APP_PORT:-8080}."
echo "Read-only local checks:"
nft list ruleset || true
ss -tulpen | grep -E ":(${APP_PORT:-8080}|${DNAT_PORT:-2024}|80|443)" || true
echo "TODO: no nftables or nginx changes in scaffold mode."
