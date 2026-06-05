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
echo "- Configure HQ-RTR DNAT port ${DOCKER_APP_PORT:-8083} to HQ-SRV web target ${DNAT_HQ_TARGET:-192.168.113.2:8083}."
echo "- Configure BR-RTR DNAT port ${DOCKER_APP_PORT:-8083} to BR-SRV docker target ${DNAT_BR_TARGET:-192.168.10.2:8083}."
echo "- Configure HQ-RTR DNAT port ${SSH_PORT:-2013} to HQ-SRV SSH target ${SSH_DNAT_HQ_TARGET:-192.168.113.2:2013}."
echo "- Configure BR-RTR DNAT port ${SSH_PORT:-2013} to BR-SRV SSH target ${SSH_DNAT_BR_TARGET:-192.168.10.2:2013}."
echo "- Configure nginx reverse proxy on ${REVERSE_PROXY_HOST:-isp.au-team.irpo}."
echo "- Proxy ${WEB_DOMAIN:-web.au-team.irpo} to HQ-SRV web."
echo "- Proxy ${DOCKER_DOMAIN:-docker.au-team.irpo} to BR-SRV site on port ${DOCKER_APP_PORT:-8083}."
echo "- Configure basic auth for ${WEB_DOMAIN:-web.au-team.irpo}: ${BASIC_AUTH_USER:-Kazimirc}, file ${BASIC_AUTH_FILE:-/etc/nginx/.htpasswd}."
echo "Read-only local checks:"
nft list ruleset || true
ss -tulpen | grep -E ":(${DOCKER_APP_PORT:-8083}|${SSH_PORT:-2013}|80|443)" || true
echo "TODO: no nftables or nginx changes in scaffold mode."
