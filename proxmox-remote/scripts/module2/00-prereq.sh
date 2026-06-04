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
echo "- Verify PDF-driven inventory variables for domain users, RAID5, NFS, Chrony role, MediaWiki, Moodle, DNAT, proxy, and HQ-CLI browser."
echo "Read-only local checks:"
hostname || true
ip -br a || true
ip route || true
cat /etc/resolv.conf || true
echo "Inventory highlights:"
echo "- domain=${DOMAIN:-au-team.irpo} realm=${REALM:-AU-TEAM.IRPO}"
echo "- users=${DOMAIN_USER_TEMPLATE:-user{N}hq} csv=${USERS_CSV_PATH:-/opt/users.csv}"
echo "- raid=RAID${RAID_LEVEL:-5} ${RAID_DEVICE:-/dev/md0} mount=${RAID_MOUNT:-/raid5}"
echo "- wiki=${WIKI_DOMAIN:-wiki.au-team.irpo} moodle=${MOODLE_DOMAIN:-moodle.au-team.irpo}"
echo "TODO: keep this file as prereq-only; do not configure heavy services here."
