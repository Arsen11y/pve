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
echo "- Configure Chrony server according to NTP_SERVER_ROLE=${NTP_SERVER_ROLE:-ISP}; candidates: ${NTP_SERVER_CANDIDATES:-isp,hq-rtr}; stratum ${NTP_STRATUM:-8}."
echo "- Current fallback time server value: ${TIME_SERVER:-isp.au-team.irpo}."
echo "- Configure HQ-SRV, HQ-CLI, BR-RTR, and BR-SRV as Chrony clients."
echo "- Install Ansible on BR-SRV in ${ANSIBLE_WORKDIR:-/etc/ansible} with hosts: ${ANSIBLE_HOSTS:-hq-srv,hq-cli,hq-rtr,br-rtr}."
echo "- Run ansible all -m ping after SSH credentials and inventory are confirmed."
echo "- Generate inventory report in ${ANSIBLE_REPORT_DIR:-/etc/ansible/PC-INFO}."
echo "- Install ${HQ_CLI_BROWSER:-Yandex Browser} on HQ-CLI when package/source is confirmed."
echo "Read-only local checks:"
timedatectl status || true
command -v ansible || true
echo "TODO: no package install, browser install, or time changes in scaffold mode."
