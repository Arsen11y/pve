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

echo "Planned Module 2 time/Ansible actions"
echo "- Configure ISP as Chrony time server: ${TIME_SERVER:-isp.au-team.irpo}."
echo "- Configure HQ-SRV, HQ-CLI, BR-RTR, and BR-SRV as Chrony clients."
echo "- Install Ansible on BR-SRV with hosts: ${ANSIBLE_HOSTS:-hq-srv,hq-cli,hq-rtr,br-rtr}."
echo "- Generate inventory report in ${ANSIBLE_REPORT_DIR:-/etc/ansible/PC-INFO}."
echo "Read-only local checks:"
timedatectl status || true
command -v ansible || true
echo "TODO: no package install or time changes in scaffold mode."
