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

echo "Planned Module 2 security/firewall actions"
echo "- Create CA with common name: ${CA_COMMON_NAME:-au-team.irpo Demo CA}."
echo "- Enable HTTPS for HQ-SRV after certificate data is confirmed."
echo "- Replace GRE with protected tunnel only after exact tunnel requirements are known."
echo "- Harden HQ-RTR/BR-RTR firewall using inventory-defined service list."
echo "Read-only local checks:"
nft list ruleset || true
ip tunnel show || true
echo "TODO: no certificate, tunnel, or firewall changes in scaffold mode."
