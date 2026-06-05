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

echo "Module 2 storage: RAID${RAID_LEVEL} on HQ-SRV"

if [[ -b "$RAID_DEVICE" ]] && findmnt -n "$RAID_MOUNT" >/dev/null 2>&1; then
  echo "[OK] already configured: $RAID_DEVICE mounted on $RAID_MOUNT"
  cat /proc/mdstat || true
  lsblk || true
  df -h "$RAID_MOUNT" || true
  return 0 2>/dev/null || exit 0
fi

safe_apt_install mdadm e2fsprogs
rescan_guest_scsi

root_source="$(findmnt -n -o SOURCE / || true)"
root_disk=""
if [[ -n "$root_source" ]]; then
  root_disk="$(lsblk -no PKNAME "$root_source" 2>/dev/null | head -n1 || true)"
  if [[ -z "$root_disk" ]]; then
    root_disk="$(basename "$root_source")"
  fi
fi

candidate_disks=()
manual_disks=(/dev/sdb /dev/sdc /dev/sdd)
manual_ok=1
for disk in "${manual_disks[@]}"; do
  [[ -b "$disk" ]] || manual_ok=0
done

if [[ "$manual_ok" -eq 1 ]]; then
  candidate_disks=("${manual_disks[@]}")
else
  while read -r name type size; do
    [[ "$type" == "disk" ]] || continue
    [[ "$name" != "$root_disk" ]] || continue
    if (( size < 800000000 || size > 1300000000 )); then
      continue
    fi
    if (( "$(lsblk -nr "/dev/$name" | wc -l)" > 1 )); then
      continue
    fi
    if lsblk -nr -o MOUNTPOINT "/dev/$name" | grep -q .; then
      continue
    fi
    if lsblk -nr -o FSTYPE "/dev/$name" | grep -q .; then
      continue
    fi
    candidate_disks+=("/dev/$name")
  done < <(lsblk -dn -b -o NAME,TYPE,SIZE)
fi

if [[ -b "$RAID_DEVICE" ]]; then
  echo "[OK] RAID device already exists: $RAID_DEVICE"
else
  if (( ${#candidate_disks[@]} < RAID_DISK_COUNT )); then
    echo "[FAIL] Not enough free ~1GB disks for RAID${RAID_LEVEL}"
    echo "Found: ${candidate_disks[*]:-none}"
    echo "Command: lsblk -dn -b -o NAME,TYPE,SIZE"
    echo "Next hint: attach ${RAID_DISK_COUNT} extra 1GB disks to HQ-SRV and rerun module2-storage"
    exit 1
  fi

  selected_disks=("${candidate_disks[@]:0:$RAID_DISK_COUNT}")
  echo "[STEP] create $RAID_DEVICE from: ${selected_disks[*]}"
  for disk in "${selected_disks[@]}"; do
    mdadm --zero-superblock --force "$disk" 2>/dev/null || true
  done
  mdadm --create "$RAID_DEVICE" --force --run --level="$RAID_LEVEL" --raid-devices="$RAID_DISK_COUNT" "${selected_disks[@]}"
  udevadm settle 2>/dev/null || true
fi

if ! blkid "$RAID_DEVICE" >/dev/null 2>&1; then
  echo "[STEP] create ext4 on $RAID_DEVICE"
  mkfs.ext4 -F "$RAID_DEVICE"
fi

mkdir -p "$RAID_MOUNT"
raid_uuid="$(blkid -s UUID -o value "$RAID_DEVICE")"
if [[ -z "$raid_uuid" ]]; then
  echo "[FAIL] Cannot read UUID for $RAID_DEVICE"
  echo "Command: blkid $RAID_DEVICE"
  echo "Next hint: check mdadm status and blkid output"
  exit 1
fi

fstab_tmp="$(mktemp)"
awk -v dev="$RAID_DEVICE" -v uuid="UUID=$raid_uuid" -v mnt="$RAID_MOUNT" \
  '$1 != dev && $1 != uuid && $2 != mnt {print}' /etc/fstab > "$fstab_tmp"
cat "$fstab_tmp" > /etc/fstab
rm -f "$fstab_tmp"
echo "UUID=$raid_uuid $RAID_MOUNT ext4 defaults,nofail 0 0" >> /etc/fstab
mount "$RAID_MOUNT" || mount -a

mdadm --detail --scan > /etc/mdadm.conf

if ! findmnt -n "$RAID_MOUNT" >/dev/null 2>&1; then
  echo "[FAIL] $RAID_MOUNT is not mounted after configuration"
  echo "Command: findmnt $RAID_MOUNT"
  echo "Next hint: check mdadm --detail $RAID_DEVICE and /etc/fstab"
  exit 1
fi

echo "[OK] RAID storage configured"
cat /proc/mdstat || true
lsblk || true
mdadm --detail "$RAID_DEVICE" || true
mount | grep "$RAID_MOUNT" || true
df -h "$RAID_MOUNT" || true
exit 0
