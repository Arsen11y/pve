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
echo "- Implemented blocks: RAID5 storage, NFS, Chrony, Ansible scaffold/check."
echo "- Planned-only blocks: Samba DC, Docker app, web stack, DNAT, proxy, basic auth, and HQ-CLI browser."
echo "Read-only local checks:"
hostname || true
ip -br a || true
ip route || true
cat /etc/resolv.conf || true
echo "Inventory highlights:"
echo "- domain=${DOMAIN:-au-team.irpo} realm=${REALM:-AU-TEAM.IRPO}"
echo "- users=${DOMAIN_USERS_PREFIX:-hquser}1-${DOMAIN_USERS_PREFIX:-hquser}${DOMAIN_USERS_COUNT:-5} csv=${USERS_CSV_PATH:-/opt/users.csv}"
echo "- raid=RAID${RAID_LEVEL:-5} ${RAID_DEVICE:-/dev/md3} mount=${RAID_MOUNT:-/raid}"
echo "- docker=${DOCKER_DOMAIN:-docker.au-team.irpo} web=${WEB_DOMAIN:-web.au-team.irpo} app_port=${DOCKER_APP_PORT:-8083}"
echo "TODO: keep this file as prereq-only; do not configure heavy services here."
