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

echo "Module 2 prereq plan"
echo "- Verify Module 1 routes, DNS, GRE/OSPF, and SSH baseline before changing services."
echo "- Verify inventory variables for domain, users, storage, web app, monitoring, logs, and backup."
echo "Read-only local checks:"
hostname || true
ip -br a || true
ip route || true
cat /etc/resolv.conf || true
echo "TODO: keep this file as prereq-only; do not configure heavy services here."
