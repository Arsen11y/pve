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

echo "Planned Module 2 logging/monitoring/backup actions"
echo "- Configure CUPS PDF printer ${PRINTER_NAME:-PDF} on HQ-SRV and default printer on HQ-CLI."
echo "- Configure rsyslog server on HQ-SRV into ${SYSLOG_DIR:-/var/log/remote} and client forwarding."
echo "- Configure monitoring at ${MON_DOMAIN:-mon.au-team.irpo} with user ${MON_USER:-admin}."
echo "- Include web stack, NFS/RAID5 state, and service configs in HQ-SRV backup scope only after exact backup requirement is confirmed."
echo "- Configure HQ-SRV backup into ${BACKUP_DIR:-/backup} after backup scope is confirmed."
echo "Read-only local checks:"
systemctl is-active rsyslog || true
findmnt "${BACKUP_DIR:-/backup}" || true
echo "TODO: no CUPS, rsyslog, monitoring, or backup changes in scaffold mode."
