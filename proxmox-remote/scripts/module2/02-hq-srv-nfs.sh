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

service_restart_enable() {
  local svc
  for svc in "$@"; do
    if systemctl cat "$svc" >/dev/null 2>&1; then
      systemctl enable "$svc" || true
      systemctl restart "$svc"
      return 0
    fi
  done
  return 1
}

install_nfs_packages() {
  if safe_apt_install nfs-server; then
    return 0
  fi
  safe_apt_install nfs-utils
}

host="$(hostname | tr '[:upper:]' '[:lower:]')"
echo "Module 2 NFS on $host"

case "$host" in
  hq-srv*)
    if ! findmnt -n "$RAID_MOUNT" >/dev/null 2>&1; then
      echo "[FAIL] $RAID_MOUNT is not mounted"
      echo "Command: findmnt $RAID_MOUNT"
      echo "Next hint: run bash run.sh run module2-storage first"
      exit 1
    fi

    install_nfs_packages
    mkdir -p "$NFS_DIR"
    chmod 0777 "$NFS_DIR"
    grep -v -F "$NFS_DIR " /etc/exports 2>/dev/null > /etc/exports.tmp || true
    mv /etc/exports.tmp /etc/exports
    echo "$NFS_DIR $HQ_CLI_NET(rw,sync,no_subtree_check,no_root_squash)" >> /etc/exports
    service_restart_enable rpcbind portmap || true
    exportfs -ra
    service_restart_enable nfs-server nfs nfsd || true
    exportfs -v
    echo "[OK] NFS export configured: $NFS_DIR -> $HQ_CLI_NET"
    ;;

  hq-cli*)
    install_nfs_packages
    mkdir -p "$NFS_CLIENT_MOUNT"
    nfs_source="$HQ_SRV_ADDR:$NFS_DIR"
    grep -v -F " $NFS_CLIENT_MOUNT " /etc/fstab > /etc/fstab.tmp || true
    mv /etc/fstab.tmp /etc/fstab
    echo "$nfs_source $NFS_CLIENT_MOUNT nfs defaults,_netdev 0 0" >> /etc/fstab
    mount "$NFS_CLIENT_MOUNT" || mount -a
    touch "$NFS_CLIENT_MOUNT/module2-test-from-hq-cli.txt"
    showmount -e "$HQ_SRV_ADDR" || true
    mount | grep "$NFS_CLIENT_MOUNT" || true
    ls -la "$NFS_CLIENT_MOUNT" || true
    echo "[OK] NFS client mount configured: $nfs_source -> $NFS_CLIENT_MOUNT"
    ;;

  *)
    echo "[FAIL] Unsupported NFS target host: $host"
    echo "Command: hostname"
    echo "Next hint: run module2-nfs only on HQ-SRV and HQ-CLI"
    exit 1
    ;;
esac
