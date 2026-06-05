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

chrony_conf_path() {
  if [[ -d /etc/chrony ]]; then
    echo /etc/chrony/chrony.conf
  else
    echo /etc/chrony.conf
  fi
}

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

host="$(hostname | tr '[:upper:]' '[:lower:]')"
conf="$(chrony_conf_path)"
mkdir -p "$(dirname "$conf")"

safe_apt_install chrony

case "$host" in
  isp*)
    cat > "$conf" <<EOFINNER
driftfile /var/lib/chrony/drift
local stratum $NTP_STRATUM
allow $HQ_SRV_NET
allow $HQ_CLI_NET
allow $BR_SRV_NET
allow $ISP_HQ_NET
allow $ISP_BR_NET
rtcsync
makestep 1.0 3
EOFINNER
    service_restart_enable chronyd chrony
    echo "[OK] ISP chrony server configured with stratum $NTP_STRATUM"
    ;;

  hq-srv*|hq-cli*)
    cat > "$conf" <<EOFINNER
server $ISP_HQ_ADDR iburst prefer
driftfile /var/lib/chrony/drift
rtcsync
makestep 1.0 3
EOFINNER
    service_restart_enable chronyd chrony
    echo "[OK] Chrony client configured with server $ISP_HQ_ADDR"
    ;;

  br-rtr*|br-srv*)
    cat > "$conf" <<EOFINNER
server $ISP_BR_ADDR iburst prefer
driftfile /var/lib/chrony/drift
rtcsync
makestep 1.0 3
EOFINNER
    service_restart_enable chronyd chrony
    echo "[OK] Chrony client configured with server $ISP_BR_ADDR"
    ;;

  *)
    echo "[FAIL] Unsupported chrony target host: $host"
    echo "Command: hostname"
    echo "Next hint: run module2-chrony only on ISP, HQ-SRV, HQ-CLI, BR-RTR, BR-SRV"
    exit 1
    ;;
esac

if command -v chronyc >/dev/null 2>&1; then
  chronyc sources || true
  chronyc tracking || true
else
  echo "[FAIL] chronyc command is unavailable"
  echo "Command: command -v chronyc"
  echo "Next hint: check chrony package installation on ALT"
fi
