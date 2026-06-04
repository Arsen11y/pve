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

echo "Planned Module 2 storage/NFS actions for HQ-SRV"
echo "- Detect ${RAID_DISK_COUNT:-3} inventory-defined extra disks of ${RAID_DISK_SIZE_GB:-1}GB each; do not assume disk names."
echo "- Create RAID${RAID_LEVEL:-5} device ${RAID_DEVICE:-/dev/md0} and mount it at ${RAID_MOUNT:-/raid5}."
echo "- Export ${NFS_DIR:-/raid5/nfs} to ${NFS_CLIENT_NET:-192.168.200.0/27}."
echo "- Configure HQ-CLI automount at ${NFS_CLIENT_MOUNT:-/mnt/nfs}."
echo "Read-only local checks:"
lsblk || true
findmnt "${RAID_MOUNT:-/raid5}" || true
echo "TODO: implement only after exact disk layout is confirmed in inventory."
