#!/usr/bin/env bash
set -euo pipefail

DEFAULT_RAW_URL="https://raw.githubusercontent.com/Arsen11y/pve/main/proxmox-remote"
DE_RAW_URL="${DE_RAW_URL:-$DEFAULT_RAW_URL}"
INV="${DE_INVENTORY:-/root/de-inventory.env}"
REQUEST_COMMAND="${1:-}"
REQUEST_SUBCOMMAND="${2:-}"
DEMO_LOG="${DEMO_LOG:-/root/module1-demo-run.log}"
MODULE1_CHECK_RESULT="${MODULE1_CHECK_RESULT:-/root/module1-check-success.txt}"
GUEST_EXEC_POLL_INTERVAL="${GUEST_EXEC_POLL_INTERVAL:-5}"
GUEST_EXEC_WAIT_TIMEOUT="${GUEST_EXEC_WAIT_TIMEOUT:-900}"
INVENTORY_LOADED=0

inventory_needs_refresh() {
  [[ ! -f "$INV" ]] && return 0
  grep -q '^VLAN_SRV=113$' "$INV" || return 0
  grep -q '^VLAN_CLI=213$' "$INV" || return 0
  grep -q '^VLAN_MGMT=813$' "$INV" || return 0
  grep -q '^SSH_PORT=2013$' "$INV" || return 0
  grep -q '^SSH_UID=2013$' "$INV" || return 0
  grep -q '^ISP_HQ_IP=172\.16\.50\.1/28$' "$INV" || return 0
  grep -q '^ISP_HQ_ADDR=172\.16\.50\.1$' "$INV" || return 0
  grep -q '^HQ_RTR_WAN_IP=172\.16\.50\.2/28$' "$INV" || return 0
  grep -q '^HQ_RTR_WAN_ADDR=172\.16\.50\.2$' "$INV" || return 0
  grep -q '^ISP_BR_IP=172\.16\.60\.1/28$' "$INV" || return 0
  grep -q '^ISP_BR_ADDR=172\.16\.60\.1$' "$INV" || return 0
  grep -q '^BR_RTR_WAN_IP=172\.16\.60\.2/28$' "$INV" || return 0
  grep -q '^BR_RTR_WAN_ADDR=172\.16\.60\.2$' "$INV" || return 0
  grep -q '^HQ_SRV_NET=192\.168\.113\.0/27$' "$INV" || return 0
  grep -q '^HQ_SRV_ADDR=192\.168\.113\.2$' "$INV" || return 0
  grep -q '^HQ_RTR_SRV_ADDR=192\.168\.113\.1$' "$INV" || return 0
  grep -q '^HQ_RTR_SRV_GW=192\.168\.113\.1$' "$INV" || return 0
  grep -q '^HQ_CLI_NET=192\.168\.213\.0/27$' "$INV" || return 0
  grep -q '^HQ_RTR_CLI_ADDR=192\.168\.213\.1$' "$INV" || return 0
  grep -q '^HQ_RTR_CLI_GW=192\.168\.213\.1$' "$INV" || return 0
  grep -q '^HQ_CLI_DHCP_START=192\.168\.213\.10$' "$INV" || return 0
  grep -q '^HQ_CLI_DHCP_END=192\.168\.213\.20$' "$INV" || return 0
  grep -q '^HQ_CLI_ADDR=192\.168\.213\.11$' "$INV" || return 0
  grep -q '^HQ_CLI_GW=192\.168\.213\.1$' "$INV" || return 0
  grep -q '^HQ_RTR_MGMT_GW=192\.168\.81\.1$' "$INV" || return 0
  grep -q '^BR_SRV_ADDR=192\.168\.10\.2$' "$INV" || return 0
  grep -q '^BR_RTR_LAN_ADDR=192\.168\.10\.1$' "$INV" || return 0
  grep -q '^GRE_NAME=gre1$' "$INV" || return 0
  grep -q '^DNS_FORWARDER_1=77\.88\.8\.7$' "$INV" || return 0
  grep -q '^DNS_FORWARDER_2=77\.88\.8\.3$' "$INV" || return 0
  grep -q '^DNS_FORWARDER_FALLBACK=8\.8\.8\.8$' "$INV" || return 0
  grep -q '^DNS_HQ_SRV_IP=192\.168\.113\.2$' "$INV" || return 0
  grep -q '^DNS_HQ_RTR_IP=192\.168\.113\.1$' "$INV" || return 0
  grep -q '^DNS_HQ_CLI_IP=192\.168\.213\.11$' "$INV" || return 0
  grep -q '^DNS_BR_SRV_IP=192\.168\.10\.2$' "$INV" || return 0
  grep -q '^DNS_BR_RTR_IP=192\.168\.10\.1$' "$INV" || return 0
  grep -q '^DNS_WEB_IP=172\.16\.50\.1$' "$INV" || return 0
  grep -q '^DNS_DOCKER_IP=172\.16\.60\.1$' "$INV" || return 0
  grep -q '^WEB_HTTP_SERVICE=' "$INV" || return 0
  grep -q '^WEB_DOCROOT=' "$INV" || return 0
  grep -q '^YANDEX_BROWSER_PACKAGE=' "$INV" || return 0
  grep -q '^YANDEX_BROWSER_BIN=' "$INV" || return 0
  grep -q '^ADDITIONAL_MOUNT=' "$INV" || return 0
  grep -q '^AD_NETBIOS_DOMAIN=' "$INV" || return 0
  return 1
}

set_module2_defaults() {
  : "${DOMAIN:=au-team.irpo}"
  : "${REALM:=AU-TEAM.IRPO}"
  : "${WEB_DOMAIN:=web.au-team.irpo}"
  : "${DOCKER_DOMAIN:=docker.au-team.irpo}"
  : "${AD_NETBIOS_DOMAIN:=AU-TEAM}"
  : "${SAMBA_DOMAIN:=$AD_NETBIOS_DOMAIN}"
  : "${SAMBA_REALM:=$REALM}"
  : "${SAMBA_ADMIN_USER:=Administrator}"
  : "${SAMBA_ADMIN_PASS:=${DOMAIN_PASS:-P@ssw0rd}}"
  : "${SAMBA_DC_HOST:=br-srv.$DOMAIN}"
  : "${SAMBA_DC_IP:=${BR_SRV_ADDR:-192.168.10.2}}"
  : "${SAMBA_GROUP:=${DOMAIN_GROUP:-hq}}"
  : "${SAMBA_USER_PREFIX:=${DOMAIN_USERS_PREFIX:-hquser}}"
  : "${SAMBA_USERS_COUNT:=${DOMAIN_USERS_COUNT:-5}}"
  : "${AD_USERS_CSV:=/mnt/additional/Users.csv}"
  : "${ADDITIONAL_MOUNT:=/mnt/additional}"
  : "${ADDITIONAL_CDROM_1:=/dev/sr0}"
  : "${ADDITIONAL_CDROM_2:=/dev/cdrom}"
  : "${RAID_DEVICE:=/dev/md3}"
  : "${RAID_LEVEL:=5}"
  : "${RAID_DISK_COUNT:=3}"
  : "${RAID_DISK_SIZE_GB:=1}"
  : "${RAID_MOUNT:=/raid}"
  : "${NFS_DIR:=/raid/nfs}"
  : "${NFS_EXPORT_DIR:=$NFS_DIR}"
  : "${NFS_CLIENT_MOUNT:=/mnt/nfs}"
  : "${NFS_MOUNT_DIR:=$NFS_CLIENT_MOUNT}"
  : "${NFS_SERVER:=${HQ_SRV_ADDR:-192.168.113.2}}"
  : "${NFS_CLIENT_NET:=192.168.213.0/27}"
  : "${NTP_SERVER_ROLE:=ISP}"
  : "${NTP_STRATUM:=8}"
  : "${ANSIBLE_WORKDIR:=/etc/ansible}"
  : "${ANSIBLE_REPORT_DIR:=/etc/ansible/PC-INFO}"
  : "${ANSIBLE_PLAYBOOK_SRC:=/mnt/additional/playbook/get_hostname_address.yml}"
  : "${DOCKER_APP_IMAGE:=site:latest}"
  : "${DOCKER_DB_IMAGE:=postgres:15-alpine}"
  : "${DOCKER_NETWORK:=examnet}"
  : "${DOCKER_APP_CONTAINER:=site}"
  : "${DOCKER_SITE_CONTAINER:=$DOCKER_APP_CONTAINER}"
  : "${DOCKER_DB_CONTAINER:=db}"
  : "${DOCKER_DB_NAME:=testdb3}"
  : "${DOCKER_DB_USER:=test3c}"
  : "${DOCKER_DB_PASS:=P@ssw0rd}"
  : "${DOCKER_APP_PORT:=8083}"
  : "${DOCKER_CONTAINER_PORT:=8000}"
  : "${DOCKER_SITE_IMAGE:=$DOCKER_APP_IMAGE}"
  : "${APP_PORT:=$DOCKER_APP_PORT}"
  : "${WEB_DB_NAME:=webdb}"
  : "${WEB_DB_USER:=web3}"
  : "${WEB_DB_PASS:=P@ssw0rd}"
  : "${WEB_DOCROOT:=/var/www/html}"
  : "${WEB_ROOT:=$WEB_DOCROOT}"
  : "${WEB_HTTP_SERVICE:=httpd2}"
  : "${WEB_DB_SERVICE:=mariadb}"
  : "${WEB_HTTP_PORT:=80}"
  : "${NGINX_SERVICE:=nginx}"
  : "${BASIC_AUTH_USER:=Kazimirc}"
  : "${BASIC_AUTH_PASS:=P@ssw0rd}"
  : "${BASIC_AUTH_FILE:=/etc/nginx/.htpasswd}"
  : "${YANDEX_BROWSER_PACKAGE:=yandex-browser-stable}"
  : "${YANDEX_BROWSER_PREINSTALL_PACKAGE:=yandex-browser-preinstall}"
  : "${YANDEX_BROWSER_BIN:=/usr/bin/yandex-browser-stable}"
  : "${DOMAIN_USERS_PREFIX:=hquser}"
  : "${DOMAIN_USERS_SUFFIX:=}"
  : "${DOMAIN_USERS_COUNT:=5}"
  : "${DOMAIN_GROUP:=hq}"
  : "${DOMAIN_PASS:=P@ssw0rd}"
  : "${NET_ADMIN_USER:=${ROUTER_ADMIN_USER:-net_admin}}"
  : "${NET_ADMIN_PASS:=${ROUTER_ADMIN_PASS:-P@ssw0rd}}"
  : "${SSH_USER:=sshuser}"
  : "${SSH_PASS:=P@ssw0rd}"
  : "${SSH_PORT:=2013}"
  : "${DNS_WEB_IP:=172.16.50.1}"
  : "${DNS_DOCKER_IP:=172.16.60.1}"
}

refresh_inventory_from_raw() {
  local action="$1"
  echo "[STEP] ${action} inventory: $INV"
  mkdir -p "$(dirname "$INV")"
  curl -fsSL "$DE_RAW_URL/inventory.example.env" > "${INV}.tmp"
  mv "${INV}.tmp" "$INV"
  echo "[OK] inventory loaded from $DE_RAW_URL/inventory.example.env"
}

load_inventory() {
  if inventory_needs_refresh; then
    refresh_inventory_from_raw "refresh"
  fi

  if [[ -f "$INV" ]]; then
    # shellcheck disable=SC1090
    source "$INV"
    set_module2_defaults
    HQ_SRV_PVE_NET="${HQ_SRV_PVE_NET:-net6}"
    HQ_CLI_PVE_NET="${HQ_CLI_PVE_NET:-net6}"
    INVENTORY_LOADED=1
    return 0
  fi

  echo "Inventory not found: $INV"
  echo "Create it on Proxmox:"
  echo "curl -fsSL \"$DE_RAW_URL/inventory.example.env\" > /root/de-inventory.env"
  echo "nano /root/de-inventory.env"
  exit 1
}

if [[ ! ( "$REQUEST_COMMAND" == "demo" && ( "$REQUEST_SUBCOMMAND" == "module1" || "$REQUEST_SUBCOMMAND" == "module2" ) ) ]]; then
  load_inventory
fi

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run this script as root on Proxmox."
    exit 1
  fi
}

usage() {
  cat <<'EOF'
run.sh - remote Proxmox runner through qemu-guest-agent.

Commands:
  check                    Check VM presence and qemu-guest-agent
  check module1            Compact Module 1 GRE/OSPF/DNS/end-to-end report
  check module2            Module 2 storage/NFS/chrony/ansible checks
  demo module1             Prepare VLANs, run all Module 1 targets, then check
  demo module2             Run Module 2 prereq, storage, NFS, chrony, ansible, then check
  prereq module2           Check Module 1 baseline before Module 2
  prepare-vlans            Add/replace Proxmox VLAN tags for HQ-SRV/HQ-CLI
  list                     Show qm list
  ifaces <target>          Show ip -br a inside VM
  status <target>          Show hostname, ip and routes inside VM
  status module1           Same as check module1
  run <target>             Run target configuration
  run module2-storage      Configure RAID5 on HQ-SRV
  run module2-nfs          Configure NFS server on HQ-SRV and mount on HQ-CLI
  run module2-chrony       Configure ISP chrony server and clients
  run module2-ansible      Configure Ansible control node on BR-SRV
  run module2-docker       Configure Docker app on BR-SRV
  run module2-web          Configure Apache/MariaDB/PHP web on HQ-SRV
  run module2-dnat         Configure DNAT on HQ-RTR and BR-RTR
  run module2-nginx        Configure nginx reverse proxy and Basic Auth on ISP
  run module2-browser      Install Yandex Browser on HQ-CLI
  run module2-samba        Configure Samba AD DC on BR-SRV and join HQ-CLI
  run module2              Run all Module 2 blocks in safe order and check

Targets:
  isp
  hq-rtr
  br-rtr
  hq-srv
  br-srv
  hq-cli
  module1
EOF
}

target_vmid() {
  case "$1" in
    isp) echo "${ISP_VMID:?ISP_VMID is empty}" ;;
    hq-rtr) echo "${HQ_RTR_VMID:?HQ_RTR_VMID is empty}" ;;
    br-rtr) echo "${BR_RTR_VMID:?BR_RTR_VMID is empty}" ;;
    hq-srv) echo "${HQ_SRV_VMID:?HQ_SRV_VMID is empty}" ;;
    br-srv) echo "${BR_SRV_VMID:?BR_SRV_VMID is empty}" ;;
    hq-cli) echo "${HQ_CLI_VMID:?HQ_CLI_VMID is empty}" ;;
    *) echo "UNKNOWN_TARGET"; return 1 ;;
  esac
}

target_script() {
  case "$1" in
    isp) echo "scripts/module1/01-isp.sh" ;;
    hq-rtr) echo "scripts/module1/02-hq-rtr.sh" ;;
    br-rtr) echo "scripts/module1/03-br-rtr.sh" ;;
    hq-srv) echo "scripts/module1/04-hq-srv.sh" ;;
    br-srv) echo "scripts/module1/05-br-srv.sh" ;;
    hq-cli) echo "scripts/module1/06-hq-cli.sh" ;;
    *) echo "UNKNOWN_SCRIPT"; return 1 ;;
  esac
}

vm_exists() {
  local vmid="$1"
  [[ -f "/etc/pve/qemu-server/${vmid}.conf" ]]
}

require_vm() {
  local target="$1"
  local vmid="$2"
  if ! vm_exists "$vmid"; then
    echo "ERROR: VM for target='$target' with VMID=$vmid was not found."
    echo
    echo "Current Proxmox VMs:"
    qm list || true
    echo
    echo "Fix VMID in $INV"
    exit 1
  fi
}

guest_ping() {
  local vmid="$1"
  qm agent "$vmid" ping >/dev/null 2>&1
}

fetch() {
  local rel="$1"
  curl -fsSL "$DE_RAW_URL/$rel"
}

base64_file() {
  local file="$1"
  if base64 --help 2>&1 | grep -q -- '-w'; then
    base64 -w0 "$file"
  else
    base64 "$file" | tr -d '\n'
  fi
}

guest_exec_capture() {
  local vmid="$1"
  local cmd="$2"
  local out_file="$3"
  local err_file="$4"
  local meta_file="$5"
  local raw_file
  local qerr_file
  local qm_rc

  raw_file="$(mktemp)"
  qerr_file="$(mktemp)"

  if qm guest exec "$vmid" -- bash -lc "$cmd" >"$raw_file" 2>"$qerr_file"; then
    qm_rc=0
  else
    qm_rc=$?
  fi

  if ! parse_guest_exec_result "$raw_file" "$qerr_file" "$out_file" "$err_file" "$meta_file" "$qm_rc"; then
    cp "$raw_file" "$out_file"
    {
      echo "Failed to run local parser for qm guest exec."
      cat "$qerr_file"
    } >"$err_file"
    {
      echo "exitcode=$qm_rc"
      echo "pid="
      echo "state=parse_failed"
    } >"$meta_file"
  fi

  if [[ "$(meta_value "$meta_file" state)" == "running" && -n "$(meta_value "$meta_file" pid)" ]]; then
    poll_guest_exec_status "$vmid" "$(meta_value "$meta_file" pid)" "$out_file" "$err_file" "$meta_file"
  fi

  rm -f "$raw_file" "$qerr_file"
}

parse_guest_exec_result() {
  local raw_file="$1"
  local qerr_file="$2"
  local out_file="$3"
  local err_file="$4"
  local meta_file="$5"
  local qm_rc="$6"

  python3 - "$raw_file" "$qerr_file" "$out_file" "$err_file" "$meta_file" "$qm_rc" <<'PY'
import json
import re
import sys

raw_path, qerr_path, out_path, err_path, meta_path, qm_rc = sys.argv[1:]
raw = open(raw_path, "r", encoding="utf-8", errors="replace").read()
qerr = open(qerr_path, "r", encoding="utf-8", errors="replace").read()
combined = raw + "\n" + qerr

try:
    data = json.loads(raw) if raw.strip() else {}
except Exception:
    data = {}

def int_field(*names):
    for name in names:
        if name in data and data[name] not in (None, ""):
            try:
                return int(data[name])
            except Exception:
                pass
    for name in names:
        pattern = rf'(?mi)^\s*{re.escape(name)}\s*[:=]\s*(-?\d+|true|false)\s*$'
        match = re.search(pattern, combined)
        if match:
            value = match.group(1).lower()
            if value == "true":
                return 1
            if value == "false":
                return 0
            return int(value)
    return None

def pid_field():
    pid = int_field("pid")
    if pid is not None:
        return pid
    match = re.search(r'(?i)\bpid\b[^0-9]*(\d+)', combined)
    if match:
        return int(match.group(1))
    return None

out = data.get("out-data", data.get("out_data", "")) or ""
err = data.get("err-data", data.get("err_data", "")) or ""
if "error" in data:
    err = (err + "\n" if err else "") + str(data["error"])
timeout_pid_message = bool(re.search(r'(?i)timeout reached.*returning pid', combined))
if qerr and not timeout_pid_message:
    err = (err + "\n" if err else "") + qerr

pid = pid_field()
exitcode = int_field("exitcode", "exit-code")
exited = int_field("exited")

if exitcode is None:
    if pid is not None:
        exitcode = 124
        state = "running"
    elif exited in (1, True):
        exitcode = 0
        state = "exited"
    elif exited in (0, False):
        exitcode = 124
        state = "running"
    else:
        exitcode = int(qm_rc)
        state = "qm_failed" if int(qm_rc) else "unknown"
else:
    state = "exited"

open(out_path, "w", encoding="utf-8").write(str(out))
open(err_path, "w", encoding="utf-8").write(str(err))
open(meta_path, "w", encoding="utf-8").write(
    f"exitcode={int(exitcode)}\npid={pid or ''}\nstate={state}\n"
)
PY
}

poll_guest_exec_status() {
  local vmid="$1"
  local pid="$2"
  local out_file="$3"
  local err_file="$4"
  local meta_file="$5"
  local status_raw_file
  local status_qerr_file
  local status_rc
  local state
  local waited=0

  while (( waited < GUEST_EXEC_WAIT_TIMEOUT )); do
    sleep "$GUEST_EXEC_POLL_INTERVAL"
    waited=$((waited + GUEST_EXEC_POLL_INTERVAL))
    status_raw_file="$(mktemp)"
    status_qerr_file="$(mktemp)"

    if qm guest exec-status "$vmid" "$pid" >"$status_raw_file" 2>"$status_qerr_file"; then
      status_rc=0
    else
      status_rc=$?
    fi

    parse_guest_exec_result "$status_raw_file" "$status_qerr_file" "$out_file" "$err_file" "$meta_file" "$status_rc"
    rm -f "$status_raw_file" "$status_qerr_file"

    state="$(meta_value "$meta_file" state)"
    if [[ "$state" == "exited" ]]; then
      return 0
    fi
    if [[ "$state" != "running" ]]; then
      return 1
    fi
  done

  {
    cat "$err_file" 2>/dev/null || true
    echo "Global guest exec wait timeout reached after ${GUEST_EXEC_WAIT_TIMEOUT}s."
    echo "Process may still be running in VM."
    echo "Next hint: qm guest exec-status $vmid $pid"
  } >"${err_file}.tmp"
  mv "${err_file}.tmp" "$err_file"
  {
    echo "exitcode=124"
    echo "pid=$pid"
    echo "state=wait_timeout"
  } >"$meta_file"
  return 1
}

meta_value() {
  local meta_file="$1"
  local key="$2"
  awk -F= -v key="$key" '$1 == key {print substr($0, length(key) + 2); exit}' "$meta_file"
}

print_file_block() {
  local title="$1"
  local file="$2"
  if [[ -s "$file" ]]; then
    echo "[$title]"
    cat "$file"
    echo
  fi
}

guest_exec_pretty() {
  local target="$1"
  local vmid="$2"
  local action="$3"
  local cmd="$4"
  local quiet_success="${5:-0}"
  local tmpdir
  local out_file
  local err_file
  local meta_file
  local exitcode
  local pid
  local state

  tmpdir="$(mktemp -d)"
  out_file="$tmpdir/stdout"
  err_file="$tmpdir/stderr"
  meta_file="$tmpdir/meta"

  guest_exec_capture "$vmid" "$cmd" "$out_file" "$err_file" "$meta_file"
  exitcode="$(meta_value "$meta_file" exitcode)"
  pid="$(meta_value "$meta_file" pid)"
  state="$(meta_value "$meta_file" state)"

  if [[ "$quiet_success" == "1" && "$exitcode" == "0" ]]; then
    rm -rf "$tmpdir"
    return 0
  fi

  echo
  echo "============================================================"
  echo "[$action] target=$target vmid=$vmid"
  echo "============================================================"
  print_file_block "STDOUT" "$out_file"
  print_file_block "STDERR" "$err_file"
  echo "[RESULT]"
  if [[ -n "$pid" ]]; then
    echo "guest_pid=$pid"
  fi
  echo "guest_exitcode=$exitcode"
  if [[ "$exitcode" == "0" ]]; then
    echo "status=OK"
  else
    echo "status=FAIL"
    if [[ "$state" == "running" && -n "$pid" ]]; then
      echo "Next hint: qm guest exec-status $vmid $pid"
    fi
  fi

  rm -rf "$tmpdir"
  [[ "$exitcode" == "0" ]]
}

install_guest_file() {
  local target="$1"
  local vmid="$2"
  local src="$3"
  local dest="$4"
  local mode="${5:-0644}"
  local b64
  local cmd

  b64="$(base64_file "$src")"
  cmd="$(cat <<EOF
set -e
mkdir -p "$(dirname "$dest")"
base64 -d > "$dest" <<'EOF_B64'
$b64
EOF_B64
chmod "$mode" "$dest"
EOF
)"

  guest_exec_pretty "$target" "$vmid" "TRANSFER" "$cmd" 1
}

stage_run_files() {
  local target="$1"
  local vmid="$2"
  local script_rel="$3"
  local tmpdir

  tmpdir="$(mktemp -d)"
  mkdir -p "$tmpdir/scripts/lib" "$tmpdir/scripts/module1" "$tmpdir/scripts/module2"
  cp "$INV" "$tmpdir/de-inventory.env"
  fetch "scripts/lib/common.sh" > "$tmpdir/scripts/lib/common.sh"
  mkdir -p "$(dirname "$tmpdir/$script_rel")"
  fetch "$script_rel" > "$tmpdir/$script_rel"

  install_guest_file "$target" "$vmid" "$tmpdir/de-inventory.env" "/tmp/de-run/de-inventory.env" 0600
  install_guest_file "$target" "$vmid" "$tmpdir/scripts/lib/common.sh" "/tmp/de-run/scripts/lib/common.sh" 0644
  install_guest_file "$target" "$vmid" "$tmpdir/$script_rel" "/tmp/de-run/$script_rel" 0644

  rm -rf "$tmpdir"
}

run_one() {
  local target="$1"
  local vmid
  local script_rel
  local cmd

  vmid="$(target_vmid "$target")"
  script_rel="$(target_script "$target")"

  require_vm "$target" "$vmid"

  echo
  echo "============================================================"
  echo "[RUN] target=$target vmid=$vmid script=$script_rel"
  echo "============================================================"

  if ! guest_ping "$vmid"; then
    echo "[FAIL] qemu-guest-agent is not available"
    echo "Next hint: inside VM run apt-get install -y qemu-guest-agent && systemctl enable --now qemu-guest-agent"
    return 1
  fi
  echo "[OK] qemu-guest-agent is available"

  stage_run_files "$target" "$vmid" "$script_rel"

  cmd="$(cat <<EOF
set -euo pipefail
set -a
source /tmp/de-run/de-inventory.env
set +a
source /tmp/de-run/scripts/lib/common.sh
source /tmp/de-run/$script_rel
EOF
)"

  if ! guest_exec_pretty "$target" "$vmid" "RUN" "$cmd"; then
    return 1
  fi
}

run_module_script() {
  local label="$1"
  local target="$2"
  local script_rel="$3"
  local vmid
  local cmd

  vmid="$(target_vmid "$target")"
  require_vm "$target" "$vmid"

  echo
  echo "============================================================"
  echo "[RUN] block=$label target=$target vmid=$vmid script=$script_rel"
  echo "============================================================"

  if ! guest_ping "$vmid"; then
    echo "[FAIL] qemu-guest-agent is not available"
    echo "Reason: qemu-guest-agent is not reachable"
    echo "Command: qm agent $vmid ping"
    echo "Next hint: start qemu-guest-agent inside target VM"
    return 1
  fi
  echo "[OK] qemu-guest-agent is available"

  stage_run_files "$target" "$vmid" "$script_rel"

  cmd="$(cat <<EOF
set -euo pipefail
set -a
source /tmp/de-run/de-inventory.env
set +a
source /tmp/de-run/scripts/lib/common.sh
source /tmp/de-run/$script_rel
EOF
)"

  guest_exec_pretty "$target" "$vmid" "RUN $label" "$cmd"
}

wait_guest_agent() {
  local target="$1"
  local vmid="$2"
  local timeout="${3:-180}"
  local waited=0
  while (( waited < timeout )); do
    if guest_ping "$vmid"; then
      echo "[OK] qemu-guest-agent available on $target"
      return 0
    fi
    sleep 5
    waited=$((waited + 5))
  done
  echo "[FAIL] qemu-guest-agent timeout on $target"
  echo "Command: qm agent $vmid ping"
  return 1
}

rescan_guest_storage() {
  local target="$1"
  local vmid="$2"
  guest_exec_pretty "$target" "$vmid" "RESCAN storage" \
    'for h in /sys/class/scsi_host/host*; do echo "- - -" > "$h/scan" 2>/dev/null || true; done; udevadm settle 2>/dev/null || true; lsblk' 1
}

ensure_hq_srv_raid_disks() {
  local vmid="${HQ_SRV_VMID:?HQ_SRV_VMID is empty}"
  local slot
  local tmpdir out_file err_file meta_file

  echo "[STEP] ensure HQ-SRV RAID disks"
  require_vm hq-srv "$vmid"
  for slot in scsi1 scsi2 scsi3; do
    if qm config "$vmid" | grep -q "^${slot}:"; then
      echo "[OK] HQ-SRV $slot already exists"
    else
      echo "[STEP] add HQ-SRV $slot local-lvm:1"
      qm set "$vmid" "--$slot" local-lvm:1
    fi
  done

  wait_guest_agent hq-srv "$vmid" 180 || return 1
  rescan_guest_storage hq-srv "$vmid" || true
  tmpdir="$(mktemp -d)"
  out_file="$tmpdir/stdout"
  err_file="$tmpdir/stderr"
  meta_file="$tmpdir/meta"
  if guest_probe "$vmid" "for h in /sys/class/scsi_host/host*; do echo '- - -' > \"\$h/scan\" 2>/dev/null || true; done; udevadm settle 2>/dev/null || true; count=\$(lsblk -dn -b -o NAME,TYPE,SIZE | awk '\$2 == \"disk\" && \$1 != \"sda\" && \$3 >= 800000000 && \$3 <= 1300000000 {c++} END {print c+0}'); echo \"extra_1g_disks=\$count\"; test \"\$count\" -ge 3" "$out_file" "$err_file" "$meta_file"; then
    module2_ok "HQ-SRV has three extra ~1G disks"
    print_file_block "STDOUT" "$out_file"
    rm -rf "$tmpdir"
    return 0
  fi
  module2_fail "HQ-SRV has three extra ~1G disks" "HQ-SRV does not see three extra ~1G disks after qm set/rescan" "if VM is already running and hotplug failed, reboot HQ-SRV and rerun m2.sh"
  print_file_block "STDOUT" "$out_file"
  print_file_block "STDERR" "$err_file"
  rm -rf "$tmpdir"
  return 1
}

find_additional_iso() {
  local storage
  while read -r storage _; do
    [[ -n "$storage" && "$storage" != "Name" ]] || continue
    pvesm list "$storage" --content iso 2>/dev/null | awk '$1 ~ /(^|\/)Additional\.iso$/ || $1 ~ /Additional\.iso$/ {print $1; exit}'
  done < <(pvesm status 2>/dev/null | awk 'NR > 1 {print $1, $2}')
}

cdrom_slot_for_vm() {
  local vmid="$1"
  local slot
  if qm config "$vmid" | grep -q 'Additional\.iso'; then
    qm config "$vmid" | awk -F: '/Additional\.iso/ {print $1; exit}'
    return 0
  fi
  for slot in ide2 ide0 ide1 ide3 sata0 sata1 sata2 sata3; do
    if ! qm config "$vmid" | grep -q "^${slot}:"; then
      echo "$slot"
      return 0
    fi
  done
  return 1
}

guest_has_cdrom() {
  local target="$1"
  local vmid="$2"
  local tmpdir out_file err_file meta_file
  tmpdir="$(mktemp -d)"
  out_file="$tmpdir/stdout"
  err_file="$tmpdir/stderr"
  meta_file="$tmpdir/meta"
  guest_probe "$vmid" 'test -b /dev/sr0 || test -b /dev/cdrom' "$out_file" "$err_file" "$meta_file"
  local ok=$?
  rm -rf "$tmpdir"
  return "$ok"
}

ensure_vm_cdrom_visible() {
  local target="$1"
  local vmid="$2"
  wait_guest_agent "$target" "$vmid" 180 || return 1
  rescan_guest_storage "$target" "$vmid" || true
  if guest_has_cdrom "$target" "$vmid"; then
    echo "[OK] $target sees Additional.iso cdrom"
    return 0
  fi

  echo "[STEP] reboot $target to detect attached Additional.iso"
  qm reboot "$vmid" || qm reset "$vmid"
  wait_guest_agent "$target" "$vmid" 240 || return 1
  rescan_guest_storage "$target" "$vmid" || true
  if guest_has_cdrom "$target" "$vmid"; then
    echo "[OK] $target sees Additional.iso cdrom after reboot"
    return 0
  fi

  echo "[FAIL] $target still does not see /dev/sr0 or /dev/cdrom"
  echo "Command: qm guest exec $vmid -- bash -lc 'lsblk; ls -l /dev/sr0 /dev/cdrom'"
  return 1
}

attach_additional_iso_to_vm() {
  local target="$1"
  local vmid="$2"
  local iso_volume="$3"
  local slot

  require_vm "$target" "$vmid"
  slot="$(cdrom_slot_for_vm "$vmid")" || {
    echo "[FAIL] no free IDE/SATA CD-ROM slot for $target VMID=$vmid"
    echo "Command: qm config $vmid"
    return 1
  }

  if qm config "$vmid" | grep -q "^${slot}:.*Additional\.iso"; then
    echo "[OK] Additional.iso already attached to $target at $slot"
  else
    echo "[STEP] attach Additional.iso to $target at $slot"
    qm set "$vmid" "--$slot" "${iso_volume},media=cdrom"
  fi

  ensure_vm_cdrom_visible "$target" "$vmid"
}

ensure_module2_additional_iso() {
  local iso_volume
  echo "[STEP] ensure Additional.iso attached"
  iso_volume="$(find_additional_iso | head -n1 || true)"
  if [[ -z "$iso_volume" ]]; then
    echo "[FAIL] Additional.iso not found in Proxmox ISO storage. Upload Additional.iso first."
    echo "Command: pvesm list <storage> --content iso"
    return 1
  fi
  echo "[OK] Additional.iso found: $iso_volume"
  attach_additional_iso_to_vm hq-srv "$HQ_SRV_VMID" "$iso_volume" || return 1
  attach_additional_iso_to_vm br-srv "$BR_SRV_VMID" "$iso_volume" || return 1
}

run_module2_storage() {
  module2_failed=0
  ensure_hq_srv_raid_disks || return 1
  run_module_script "module2-storage" hq-srv "scripts/module2/01-hq-srv-storage.sh"
}

run_module2_nfs() {
  run_module_script "module2-nfs server" hq-srv "scripts/module2/02-hq-srv-nfs.sh" || return 1
  run_module_script "module2-nfs client" hq-cli "scripts/module2/02-hq-srv-nfs.sh" || return 1
}

run_module2_chrony() {
  run_module_script "module2-chrony server" isp "scripts/module2/03-chrony.sh" || return 1
  run_module_script "module2-chrony hq-srv" hq-srv "scripts/module2/03-chrony.sh" || return 1
  run_module_script "module2-chrony hq-cli" hq-cli "scripts/module2/03-chrony.sh" || return 1
  run_module_script "module2-chrony br-rtr" br-rtr "scripts/module2/03-chrony.sh" || return 1
  run_module_script "module2-chrony br-srv" br-srv "scripts/module2/03-chrony.sh" || return 1
}

run_module2_ansible() {
  run_module_script "module2-ansible hq-cli ssh" hq-cli "scripts/module2/04-br-srv-ansible.sh" || return 1
  run_module_script "module2-ansible hq-rtr ssh" hq-rtr "scripts/module2/04-br-srv-ansible.sh" || return 1
  run_module_script "module2-ansible br-rtr ssh" br-rtr "scripts/module2/04-br-srv-ansible.sh" || return 1
  run_module_script "module2-ansible controller" br-srv "scripts/module2/04-br-srv-ansible.sh" || return 1
}

run_module2_docker() {
  ensure_module2_additional_iso || return 1
  run_module_script "module2-docker" br-srv "scripts/module2/04-web-docker.sh"
}

run_module2_web() {
  ensure_module2_additional_iso || return 1
  run_module_script "module2-web" hq-srv "scripts/module2/05-hq-srv-web.sh"
}

run_module2_dnat() {
  run_module_script "module2-dnat hq-rtr" hq-rtr "scripts/module2/05-proxy-dnat.sh" || return 1
  run_module_script "module2-dnat br-rtr" br-rtr "scripts/module2/05-proxy-dnat.sh" || return 1
}

run_module2_nginx() {
  run_module_script "module2-nginx" isp "scripts/module2/06-security-firewall.sh"
}

run_module2_browser() {
  run_module_script "module2-browser" hq-cli "scripts/module2/08-hq-cli-browser.sh"
}

run_module2_samba() {
  run_module_script "module2-samba dc" br-srv "scripts/module2/02-br-srv-domain.sh" || return 1
  run_module_script "module2-samba join" hq-cli "scripts/module2/02-br-srv-domain.sh" || return 1
}

run_module2_all() {
  show_module2_prereq || return 1
  run_module2_storage || return 1
  run_module2_nfs || return 1
  run_module2_chrony || return 1
  run_module2_ansible || return 1
  run_module2_docker || return 1
  run_module2_web || return 1
  run_module2_dnat || return 1
  run_module2_nginx || return 1
  run_module2_browser || return 1
  run_module2_samba || return 1
  show_module2_status
}

check_all() {
  echo "DE_RAW_URL=$DE_RAW_URL"
  echo "INVENTORY=$INV"
  echo
  qm list
  echo
  for target in isp hq-rtr hq-srv hq-cli br-rtr br-srv; do
    vmid="$(target_vmid "$target")"
    printf "%-7s VMID=%-6s " "$target" "$vmid"
    if ! vm_exists "$vmid"; then
      echo "NO_VM"
      continue
    fi
    if guest_ping "$vmid"; then
      echo "AGENT_OK"
    else
      echo "AGENT_FAIL"
    fi
  done
}

show_ifaces() {
  local target="$1"
  local vmid
  vmid="$(target_vmid "$target")"
  require_vm "$target" "$vmid"
  guest_exec_pretty "$target" "$vmid" "IFACES" "ip -br a"
}

show_status() {
  local target="$1"
  local vmid
  vmid="$(target_vmid "$target")"
  require_vm "$target" "$vmid"
  guest_exec_pretty "$target" "$vmid" "STATUS" "hostname; echo '--- ip ---'; ip -br a; echo '--- route ---'; ip route"
}

guest_probe() {
  local vmid="$1"
  local cmd="$2"
  local out_file="$3"
  local err_file="$4"
  local meta_file="$5"
  local exitcode

  guest_exec_capture "$vmid" "$cmd" "$out_file" "$err_file" "$meta_file"
  exitcode="$(meta_value "$meta_file" exitcode)"
  [[ "$exitcode" == "0" ]]
}

module_check_failed=0

module_check_item() {
  local label="$1"
  local vmid="$2"
  local cmd="$3"
  local reason="$4"
  local hint="$5"
  local tmpdir
  local out_file
  local err_file
  local meta_file

  tmpdir="$(mktemp -d)"
  out_file="$tmpdir/stdout"
  err_file="$tmpdir/stderr"
  meta_file="$tmpdir/meta"

  if guest_probe "$vmid" "$cmd" "$out_file" "$err_file" "$meta_file"; then
    echo "[OK] $label"
  else
    module_check_failed=1
    echo "[FAIL] $label"
    echo "Reason: $reason"
    echo "Command: $cmd"
    echo "Next hint: $hint"
    print_file_block "STDOUT" "$out_file"
    print_file_block "STDERR" "$err_file"
  fi

  rm -rf "$tmpdir"
}

show_module1_status() {
  echo
  echo "============================================================"
  echo "MODULE 1 CHECK SUMMARY"
  echo "======================"
  echo

  module_check_failed=0
  module_check_item "ISP NAT and internet" "$ISP_VMID" \
    "ping -c 4 8.8.8.8 >/dev/null" \
    "ISP cannot ping 8.8.8.8" \
    "check ip route, nft list ruleset, and ISP WAN DHCP"

  module_check_item "HQ-RTR GRE tunnel" "$HQ_RTR_VMID" \
    "ip tunnel show $GRE_NAME | grep -q \"remote $BR_RTR_WAN_ADDR\" && ping -c 4 $GRE_BR_ADDR >/dev/null" \
    "$GRE_NAME is missing or $GRE_BR_ADDR is unreachable" \
    "check systemctl status gre1-demo --no-pager and ip tunnel show $GRE_NAME"

  module_check_item "BR-RTR GRE tunnel" "$BR_RTR_VMID" \
    "ip tunnel show $GRE_NAME | grep -q \"remote $HQ_RTR_WAN_ADDR\" && ping -c 4 $GRE_HQ_ADDR >/dev/null" \
    "$GRE_NAME is missing or $GRE_HQ_ADDR is unreachable" \
    "check systemctl status gre1-demo --no-pager and ip tunnel show $GRE_NAME"

  module_check_item "HQ-RTR VLAN $VLAN_SRV/$VLAN_CLI/$VLAN_MGMT interfaces" "$HQ_RTR_VMID" \
    "ip -br a | grep -q \"$HQ_RTR_LAN_IF.$VLAN_SRV\" && ip -br a | grep -q \"$HQ_RTR_LAN_IF.$VLAN_CLI\" && ip -br a | grep -q \"$HQ_RTR_LAN_IF.$VLAN_MGMT\"" \
    "HQ-RTR VLAN interfaces are missing" \
    "check /etc/net/ifaces/$HQ_RTR_LAN_IF.$VLAN_SRV and systemctl restart network"

  module_check_item "OSPF neighbor Full on HQ-RTR" "$HQ_RTR_VMID" \
    "vtysh -c 'show ip ospf neighbor' | grep -q Full" \
    "OSPF neighbor is not Full on HQ-RTR" \
    "check vtysh -c 'show ip ospf neighbor' and journalctl -u frr --no-pager -n 80"

  module_check_item "OSPF neighbor Full on BR-RTR" "$BR_RTR_VMID" \
    "vtysh -c 'show ip ospf neighbor' | grep -q Full" \
    "OSPF neighbor is not Full on BR-RTR" \
    "check vtysh -c 'show ip ospf neighbor' and journalctl -u frr --no-pager -n 80"

  module_check_item "DNS service on HQ-SRV" "$HQ_SRV_VMID" \
    "systemctl is-active --quiet named-direct && ss -tulpen | grep -q ':53' && dig +short @127.0.0.1 hq-srv.$DOMAIN | grep -qx $HQ_SRV_ADDR && dig +short @$HQ_SRV_ADDR hq-srv.$DOMAIN | grep -qx $HQ_SRV_ADDR" \
    "named-direct.service inactive or DNS port/queries failed" \
    "check journalctl -u named-direct --no-pager -n 80"

  module_check_item "DNS records hq-srv/web/docker" "$HQ_SRV_VMID" \
    "test \"\$(dig +short @127.0.0.1 hq-srv.$DOMAIN)\" = $HQ_SRV_ADDR && test \"\$(dig +short @127.0.0.1 web.$DOMAIN)\" = $DNS_WEB_IP && test \"\$(dig +short @127.0.0.1 docker.$DOMAIN)\" = $DNS_DOCKER_IP" \
    "DNS records hq-srv/web/docker do not match expected addresses" \
    "check /var/lib/bind/etc/zones/au-team.irpo.zone and named-checkconf -t /var/lib/bind /etc/named-direct.conf"

  module_check_item "SSH $SSH_PORT listens on HQ-SRV" "$HQ_SRV_VMID" \
    "ss -tulpen | grep -q ':$SSH_PORT'" \
    "sshd is not listening on port $SSH_PORT on HQ-SRV" \
    "check systemctl status sshd --no-pager"

  module_check_item "SSH $SSH_PORT listens on BR-SRV" "$BR_SRV_VMID" \
    "ss -tulpen | grep -q ':$SSH_PORT'" \
    "sshd is not listening on port $SSH_PORT on BR-SRV" \
    "check systemctl status sshd --no-pager"

  module_check_item "HQ-SRV -> BR-SRV ping" "$HQ_SRV_VMID" \
    "ping -c 4 $BR_SRV_ADDR >/dev/null" \
    "HQ-SRV cannot reach BR-SRV" \
    "check OSPF routes and BR-SRV gateway"

  module_check_item "HQ-CLI -> BR-SRV ping" "$HQ_CLI_VMID" \
    "ping -c 4 $BR_SRV_ADDR >/dev/null" \
    "HQ-CLI cannot reach BR-SRV" \
    "check DHCP lease, default route, and OSPF routes"

  module_check_item "BR-SRV -> HQ-SRV ping" "$BR_SRV_VMID" \
    "ping -c 4 $HQ_SRV_ADDR >/dev/null" \
    "BR-SRV cannot reach HQ-SRV" \
    "check BR-SRV gateway and OSPF routes"

  module_check_item "BR-SRV -> HQ-CLI ping" "$BR_SRV_VMID" \
    "ping -c 4 $HQ_CLI_EXPECTED_IP >/dev/null || ping -c 4 $HQ_CLI_DHCP_START >/dev/null" \
    "BR-SRV cannot reach HQ-CLI on $HQ_CLI_EXPECTED_IP or $HQ_CLI_DHCP_START" \
    "check HQ-CLI DHCP lease and OSPF route to $HQ_CLI_NET"

  echo
  if [[ "$module_check_failed" -eq 0 ]]; then
    echo "RESULT: MODULE 1 PASSED"
  else
    echo "RESULT: MODULE 1 FAILED"
    return 1
  fi
}

set_vm_net_tag() {
  local target="$1"
  local vmid="$2"
  local net_key="$3"
  local tag="$4"
  local expected_bridge="$5"
  local current
  local updated

  current="$(qm config "$vmid" | awk -v key="${net_key}:" '$1 == key {sub("^[^ ]+ ", ""); print; exit}')"
  if [[ -z "$current" ]]; then
    echo "[FAIL] $target VMID=$vmid has no $net_key in qm config"
    return 1
  fi

  if [[ "$current" != *"bridge=$expected_bridge"* ]]; then
    echo "[WARN] $target $net_key bridge differs from expected $expected_bridge: $current"
  fi

  updated="$(printf '%s' "$current" | sed -E 's/,tag=[^,]+//g'),tag=$tag"
  if [[ "$current" == "$updated" ]]; then
    echo "[OK] $target VMID=$vmid $net_key already has tag=$tag"
    return 0
  fi

  qm set "$vmid" "--$net_key" "$updated"
  echo "[OK] $target VMID=$vmid $net_key updated: $updated"
}

prepare_vlans() {
  echo
  echo "============================================================"
  echo "PREPARE PROXMOX VLAN TAGS"
  echo "============================================================"
  set_vm_net_tag "hq-srv" "$HQ_SRV_VMID" "$HQ_SRV_PVE_NET" "$VLAN_SRV" "vmbr1003"
  set_vm_net_tag "hq-cli" "$HQ_CLI_VMID" "$HQ_CLI_PVE_NET" "$VLAN_CLI" "vmbr1003"
}

ensure_demo_inventory() {
  if inventory_needs_refresh; then
    refresh_inventory_from_raw "refresh"
    INVENTORY_LOADED=0
    return 0
  fi

  if [[ -f "$INV" ]]; then
    echo "[OK] inventory is current: $INV"
    return 0
  fi
}

check_proxmox_internet() {
  echo "[STEP] check Proxmox internet"
  if curl -fsSL --connect-timeout 10 "$DE_RAW_URL/run.sh" >/dev/null; then
    echo "[OK] Proxmox can reach $DE_RAW_URL"
  else
    echo "[FAIL] Proxmox cannot reach $DE_RAW_URL"
    echo "Next hint: check Proxmox DNS/default route and try: curl -I $DE_RAW_URL/run.sh"
    return 1
  fi
}

demo_step() {
  local label="$1"
  shift

  echo
  echo "[STEP] $label"
  if "$@"; then
    echo "[OK] $label"
    return 0
  fi

  echo "[FAIL] $label"
  return 1
}

write_module1_result() {
  local result="$1"
  echo "$result" > "$MODULE1_CHECK_RESULT"
  echo "$result"
  echo "Check result saved to $MODULE1_CHECK_RESULT"
}

demo_module1_failed() {
  write_module1_result "RESULT: MODULE 1 FAILED"
  echo "Full demo log: $DEMO_LOG"
  return 1
}

demo_module1() {
  mkdir -p "$(dirname "$DEMO_LOG")"
  : > "$DEMO_LOG"
  exec > >(tee -a "$DEMO_LOG") 2>&1

  echo "============================================================"
  echo "MODULE 1 DEMO RUN"
  echo "============================================================"
  echo "DE_RAW_URL=$DE_RAW_URL"
  echo "INVENTORY=$INV"
  echo "LOG=$DEMO_LOG"
  echo

  if ! check_proxmox_internet; then
    demo_module1_failed
    return 1
  fi
  if ! ensure_demo_inventory; then
    demo_module1_failed
    return 1
  fi

  if [[ "$INVENTORY_LOADED" -ne 1 ]]; then
    load_inventory
  fi

  if ! demo_step "prepare-vlans" prepare_vlans; then
    demo_module1_failed
    return 1
  fi
  if ! demo_step "run isp" run_one isp; then
    demo_module1_failed
    return 1
  fi
  if ! demo_step "run hq-rtr" run_one hq-rtr; then
    demo_module1_failed
    return 1
  fi
  if ! demo_step "run br-rtr" run_one br-rtr; then
    demo_module1_failed
    return 1
  fi
  if ! demo_step "run hq-srv" run_one hq-srv; then
    demo_module1_failed
    return 1
  fi
  if ! demo_step "run br-srv" run_one br-srv; then
    demo_module1_failed
    return 1
  fi
  if ! demo_step "run hq-cli" run_one hq-cli; then
    demo_module1_failed
    return 1
  fi

  if demo_step "check module1" show_module1_status; then
    write_module1_result "RESULT: MODULE 1 PASSED"
    echo "Full demo log: $DEMO_LOG"
    return 0
  fi

  demo_module1_failed
}

module2_failed=0

module2_fail() {
  local label="$1"
  local reason="$2"
  local hint="$3"

  module2_failed=1
  echo "[FAIL] $label"
  echo "Reason: $reason"
  echo "Next hint: $hint"
}

module2_ok() {
  local label="$1"
  echo "[OK] $label"
}

module2_agent_check() {
  local label="$1"
  local vmid="$2"

  if guest_ping "$vmid"; then
    module2_ok "$label"
  else
    module2_fail "$label" "qemu-guest-agent is not reachable" "check VM power state and qemu-guest-agent service"
  fi
}

module2_guest_check() {
  local label="$1"
  local vmid="$2"
  local cmd="$3"
  local reason="$4"
  local hint="$5"
  local tmpdir
  local out_file
  local err_file
  local meta_file

  tmpdir="$(mktemp -d)"
  out_file="$tmpdir/stdout"
  err_file="$tmpdir/stderr"
  meta_file="$tmpdir/meta"

  if guest_probe "$vmid" "$cmd" "$out_file" "$err_file" "$meta_file"; then
    module2_ok "$label"
  else
    module2_fail "$label" "$reason" "$hint"
    print_file_block "STDOUT" "$out_file"
    print_file_block "STDERR" "$err_file"
  fi

  rm -rf "$tmpdir"
}

show_module2_prereq() {
  if [[ "$INVENTORY_LOADED" -ne 1 ]]; then
    load_inventory
  fi

  echo
  echo "============================================================"
  echo "MODULE 2 PREREQ CHECK SUMMARY"
  echo "============================="
  echo

  module2_failed=0

  if show_module1_status; then
    module2_ok "Module 1 check passed"
  else
    module2_fail "Module 1 check passed" "Module 1 check failed" "run: bash run.sh check module1"
  fi

  module2_agent_check "HQ-SRV reachable" "$HQ_SRV_VMID"
  module2_agent_check "BR-SRV reachable" "$BR_SRV_VMID"
  module2_agent_check "HQ-CLI reachable" "$HQ_CLI_VMID"
  module2_agent_check "HQ-RTR reachable" "$HQ_RTR_VMID"
  module2_agent_check "BR-RTR reachable" "$BR_RTR_VMID"

  if ! ensure_hq_srv_raid_disks; then
    :
  fi

  if ensure_module2_additional_iso; then
    module2_ok "Additional.iso attached to HQ-SRV and BR-SRV"
  else
    module2_fail "Additional.iso attached to HQ-SRV and BR-SRV" "Additional.iso is missing or not visible in guests" "upload Additional.iso to Proxmox ISO storage and rerun m2.sh"
  fi

  module2_guest_check "DNS hq-srv/web/docker works" "$HQ_SRV_VMID" \
    "test \"\$(dig +short @127.0.0.1 hq-srv.${DOMAIN})\" = $HQ_SRV_ADDR && test \"\$(dig +short @127.0.0.1 web.${DOMAIN})\" = $DNS_WEB_IP && test \"\$(dig +short @127.0.0.1 docker.${DOMAIN})\" = $DNS_DOCKER_IP" \
    "DNS records do not match expected Module 1 values" \
    "check named-direct and zone files on HQ-SRV"

  module2_guest_check "SSH $SSH_PORT listens on HQ-SRV" "$HQ_SRV_VMID" \
    "ss -tulpen | grep -q ':$SSH_PORT'" \
    "sshd is not listening on port $SSH_PORT on HQ-SRV" \
    "check systemctl status sshd --no-pager"

  module2_guest_check "SSH $SSH_PORT listens on BR-SRV" "$BR_SRV_VMID" \
    "ss -tulpen | grep -q ':$SSH_PORT'" \
    "sshd is not listening on port $SSH_PORT on BR-SRV" \
    "check systemctl status sshd --no-pager"

  module2_guest_check "HQ-CLI has address from $HQ_CLI_NET" "$HQ_CLI_VMID" \
    "ip -4 -o addr show dev $HQ_CLI_IF | awk '{print \$4}' | grep -q '^192\\.168\\.213\\.'" \
    "HQ-CLI does not have a 192.168.213.x IPv4 address" \
    "run Module 1 again or check DHCP on HQ-RTR"

  echo
  if [[ "$module2_failed" -eq 0 ]]; then
    echo "RESULT: MODULE 2 PREREQ PASSED"
  else
    echo "RESULT: MODULE 2 PREREQ FAILED"
    echo "Run first:"
    echo "curl -fsSL https://raw.githubusercontent.com/Arsen11y/pve/main/m1.sh | bash"
    return 1
  fi
}


show_module2_status() {
  if [[ "$INVENTORY_LOADED" -ne 1 ]]; then
    load_inventory
  fi

  echo
  echo "============================================================"
  echo "MODULE 2 CHECK SUMMARY"
  echo "============================================================"
  echo

  module2_failed=0

  if show_module2_prereq; then
    module2_ok "Module 1 prerequisite"
  else
    module2_fail "Module 1 prerequisite" "Module 1 prereq failed" "Run first: curl -fsSL https://raw.githubusercontent.com/Arsen11y/pve/main/m1.sh | bash"
  fi

  module2_guest_check "RAID5 $RAID_DEVICE mounted on $RAID_MOUNT" "$HQ_SRV_VMID" \
    "test -e $RAID_DEVICE && grep -q '${RAID_DEVICE##/dev/}' /proc/mdstat && grep -q '\\[3/3\\].*\\[UUU\\]' /proc/mdstat && mdadm --detail $RAID_DEVICE | grep -q 'Raid Level : raid5' && findmnt -n $RAID_MOUNT >/dev/null && findmnt -n -o FSTYPE $RAID_MOUNT | grep -q '^ext4$' && grep -q '$RAID_MOUNT' /etc/fstab && test -f /etc/mdadm.conf" \
    "$RAID_DEVICE is missing, degraded, not raid5, or $RAID_MOUNT is not mounted as ext4" \
    "run: bash run.sh run module2-storage"

  module2_guest_check "NFS export and HQ-CLI mount" "$HQ_SRV_VMID" \
    "test -d $NFS_DIR && exportfs -v | grep -q '$NFS_DIR' && exportfs -v | grep -q '${HQ_CLI_NET%/*}' && test -f $NFS_DIR/module2-test-from-hq-cli.txt" \
    "$NFS_DIR is not exported to $HQ_CLI_NET or HQ-CLI test file is missing" \
    "run: bash run.sh run module2-nfs"

  module2_guest_check "HQ-CLI NFS mount $NFS_CLIENT_MOUNT" "$HQ_CLI_VMID" \
    "findmnt -n $NFS_CLIENT_MOUNT >/dev/null && touch $NFS_CLIENT_MOUNT/module2-check-from-hq-cli.txt" \
    "$NFS_CLIENT_MOUNT is not mounted or is not writable from HQ-CLI" \
    "check /etc/fstab on HQ-CLI and exportfs -v on HQ-SRV"

  module2_guest_check "Chrony time sync" "$ISP_VMID" \
    "(systemctl is-active --quiet chronyd || systemctl is-active --quiet chrony) && command -v chronyc >/dev/null 2>&1 && chronyc tracking | grep -q 'Stratum[[:space:]]*:[[:space:]]*$NTP_STRATUM'" \
    "chrony service is not active on ISP or stratum is not $NTP_STRATUM" \
    "run: bash run.sh run module2-chrony"

  module2_guest_check "Chrony client HQ-SRV" "$HQ_SRV_VMID" \
    "(systemctl is-active --quiet chronyd || systemctl is-active --quiet chrony) && command -v chronyc >/dev/null 2>&1 && (chronyc sources | grep -q '$ISP_HQ_ADDR' || chronyc tracking | grep -q 'Reference ID')" \
    "chrony client is not active on HQ-SRV" \
    "run: bash run.sh run module2-chrony"
  module2_guest_check "Chrony client HQ-CLI" "$HQ_CLI_VMID" \
    "(systemctl is-active --quiet chronyd || systemctl is-active --quiet chrony) && command -v chronyc >/dev/null 2>&1 && (chronyc sources | grep -q '$ISP_HQ_ADDR' || chronyc tracking | grep -q 'Reference ID')" \
    "chrony client is not active on HQ-CLI" \
    "run: bash run.sh run module2-chrony"
  module2_guest_check "Chrony client BR-RTR" "$BR_RTR_VMID" \
    "(systemctl is-active --quiet chronyd || systemctl is-active --quiet chrony) && command -v chronyc >/dev/null 2>&1 && (chronyc sources | grep -q '$ISP_BR_ADDR\\|_gateway' || chronyc tracking | grep -q 'Reference ID')" \
    "chrony client is not active on BR-RTR" \
    "run: bash run.sh run module2-chrony"
  module2_guest_check "Chrony client BR-SRV" "$BR_SRV_VMID" \
    "(systemctl is-active --quiet chronyd || systemctl is-active --quiet chrony) && command -v chronyc >/dev/null 2>&1 && (chronyc sources | grep -q '$ISP_BR_ADDR\\|_gateway' || chronyc tracking | grep -q 'Reference ID')" \
    "chrony client is not active on BR-SRV" \
    "run: bash run.sh run module2-chrony"

  module2_guest_check "Ansible inventory and ping" "$BR_SRV_VMID" \
    "test -f $ANSIBLE_WORKDIR/hosts && command -v ansible >/dev/null 2>&1 && ansible --version >/dev/null && cd $ANSIBLE_WORKDIR && ansible all -m ping | tee /tmp/module2-ansible-ping.txt && grep -q 'hq-srv.*SUCCESS' /tmp/module2-ansible-ping.txt && grep -q 'hq-cli.*SUCCESS' /tmp/module2-ansible-ping.txt && grep -q 'hq-rtr.*SUCCESS' /tmp/module2-ansible-ping.txt && grep -q 'br-rtr.*SUCCESS' /tmp/module2-ansible-ping.txt" \
    "ansible inventory is missing or ansible ping did not return SUCCESS for all expected hosts" \
    "run: bash run.sh run module2-ansible"

  module2_guest_check "Docker app on BR-SRV" "$BR_SRV_VMID" \
    "docker ps --format '{{.Names}} {{.Status}}' | grep -q '^$DOCKER_DB_CONTAINER .*Up' && docker ps --format '{{.Names}} {{.Status}}' | grep -q '^$DOCKER_APP_CONTAINER .*Up' && ss -tulpen | grep -q ':$DOCKER_APP_PORT'" \
    "Docker containers $DOCKER_DB_CONTAINER/$DOCKER_APP_CONTAINER are not Up or port $DOCKER_APP_PORT is not listening" \
    "run: bash run.sh run module2-docker"

  module2_guest_check "Docker app HTTP from HQ-CLI" "$HQ_CLI_VMID" \
    "url='http://$BR_SRV_ADDR:$DOCKER_APP_PORT'; if command -v curl >/dev/null 2>&1; then curl -fsSL \"\$url\"; else wget -qO- \"\$url\"; fi | grep -qi '<html\\|uvicorn\\|student'" \
    "GET http://$BR_SRV_ADDR:$DOCKER_APP_PORT from HQ-CLI did not return app HTML" \
    "check docker logs site and firewall/routes"

  module2_guest_check "Web service on HQ-SRV" "$HQ_SRV_VMID" \
    "(systemctl is-active --quiet $WEB_HTTP_SERVICE || systemctl is-active --quiet apache2 || systemctl is-active --quiet httpd) && (systemctl is-active --quiet mariadb || systemctl is-active --quiet mysqld) && ss -tulpen | grep -q ':80' && test -f $WEB_DOCROOT/index.php && ! grep -qi 'It works' $WEB_DOCROOT/index.php" \
    "Apache/PHP/MariaDB web stack is not active or index.php is missing" \
    "run: bash run.sh run module2-web"

  module2_guest_check "Web service HTTP from HQ-CLI" "$HQ_CLI_VMID" \
    "url='http://$HQ_SRV_ADDR'; if command -v curl >/dev/null 2>&1; then curl -fsSL -D /tmp/module2-web-hdr \"\$url\" -o /tmp/module2-web-body; else wget -S -O /tmp/module2-web-body \"\$url\" 2>/tmp/module2-web-hdr; fi; grep -q '200\\|HTTP/.* 200' /tmp/module2-web-hdr && grep -qi '<html\\|php\\|database\\|employee' /tmp/module2-web-body && ! grep -qi 'It works' /tmp/module2-web-body" \
    "GET http://$HQ_SRV_ADDR from HQ-CLI did not return expected HQ-SRV web page" \
    "check $WEB_DOCROOT/index.php, database credentials, and Apache DocumentRoot"

  module2_guest_check "DNAT rules and access" "$ISP_VMID" \
    "timeout 5 bash -c 'cat < /dev/null > /dev/tcp/$HQ_RTR_WAN_ADDR/$SSH_PORT' && timeout 5 bash -c 'cat < /dev/null > /dev/tcp/$HQ_RTR_WAN_ADDR/$DOCKER_APP_PORT' && timeout 5 bash -c 'cat < /dev/null > /dev/tcp/$BR_RTR_WAN_ADDR/$SSH_PORT' && timeout 5 bash -c 'cat < /dev/null > /dev/tcp/$BR_RTR_WAN_ADDR/$DOCKER_APP_PORT'" \
    "DNAT ports are not reachable from ISP" \
    "run: bash run.sh run module2-dnat"

  module2_guest_check "Nginx reverse proxy" "$ISP_VMID" \
    "systemctl is-active --quiet nginx && ss -tulpen | grep -q ':80' && wget -qO- --header='Host: $DOCKER_DOMAIN' http://127.0.0.1 | grep -qi '<html\\|uvicorn\\|student'" \
    "nginx is inactive or docker reverse proxy does not return app HTML" \
    "run: bash run.sh run module2-nginx"

  module2_guest_check "Basic Auth" "$ISP_VMID" \
    "wget -S -O - --header='Host: $WEB_DOMAIN' http://127.0.0.1 2>&1 | grep -q '401 Unauthorized' && wget --user='$BASIC_AUTH_USER' --password='$BASIC_AUTH_PASS' -qO- --header='Host: $WEB_DOMAIN' http://127.0.0.1 | grep -qi '<html\\|php\\|database\\|employee'" \
    "web.au-team.irpo auth did not return 401 without credentials and 200/content with credentials" \
    "check $BASIC_AUTH_FILE permissions and nginx proxy_pass"

  module2_guest_check "Samba DNS web/docker records" "$BR_SRV_VMID" \
    "host $WEB_DOMAIN 127.0.0.1 | grep -q '$DNS_WEB_IP' && host $DOCKER_DOMAIN 127.0.0.1 | grep -q '$DNS_DOCKER_IP'" \
    "Samba DNS does not resolve web/docker to ISP addresses" \
    "run: bash run.sh run module2-samba"

  module2_guest_check "Nginx and Basic Auth from HQ-CLI" "$HQ_CLI_VMID" \
    "(getent hosts $WEB_DOMAIN || host $WEB_DOMAIN) | grep -q '$DNS_WEB_IP' && (getent hosts $DOCKER_DOMAIN || host $DOCKER_DOMAIN) | grep -q '$DNS_DOCKER_IP' && curl -s -o /tmp/module2-web-noauth -w '%{http_code}' http://$WEB_DOMAIN | grep -q '^401$' && curl -fsSL -u '$BASIC_AUTH_USER:$BASIC_AUTH_PASS' http://$WEB_DOMAIN | grep -qi '<html\\|php\\|database\\|employee' && curl -fsSL http://$DOCKER_DOMAIN | grep -qi '<html\\|uvicorn\\|student'" \
    "HQ-CLI reverse proxy checks for web/docker domains failed" \
    "check HQ-CLI DNS after domain join, Samba DNS web/docker records, nginx on ISP, DNAT, and basic auth"

  module2_guest_check "Yandex Browser" "$HQ_CLI_VMID" \
    "rpm -qa | grep -q '$YANDEX_BROWSER_PACKAGE' && test -x '$YANDEX_BROWSER_BIN' && test -f /usr/share/applications/yandex-browser.desktop && '$YANDEX_BROWSER_BIN' --version | grep -qi Yandex" \
    "Yandex Browser package/binary/desktop/version check failed" \
    "run: bash run.sh run module2-browser"

  module2_guest_check "Samba AD DC" "$BR_SRV_VMID" \
    "samba-tool domain info 127.0.0.1 | grep -qi 'Forest.*$DOMAIN' && host -t SRV _ldap._tcp.$DOMAIN 127.0.0.1 >/dev/null && host -t SRV _kerberos._udp.$DOMAIN 127.0.0.1 >/dev/null" \
    "Samba AD DC domain info or SRV records failed" \
    "run: bash run.sh run module2-samba"

  module2_guest_check "Domain users and hq group" "$BR_SRV_VMID" \
    "for i in 1 2 3 4 5; do samba-tool user list | grep -q '${DOMAIN_USERS_PREFIX}'\"\$i\"'${DOMAIN_USERS_SUFFIX}'; done && samba-tool group listmembers $DOMAIN_GROUP | grep -q '${DOMAIN_USERS_PREFIX}1${DOMAIN_USERS_SUFFIX}' && wbinfo -u | grep -q '${DOMAIN_USERS_PREFIX}1${DOMAIN_USERS_SUFFIX}'" \
    "Domain users hquser1-hquser5 or group hq membership missing" \
    "check samba-tool user list and samba-tool group listmembers $DOMAIN_GROUP"

  module2_guest_check "HQ-CLI joined to domain" "$HQ_CLI_VMID" \
    "net ads testjoin | grep -q 'Join is OK' && wbinfo -t && wbinfo -u | grep -q '${DOMAIN_USERS_PREFIX}1${DOMAIN_USERS_SUFFIX}' && wbinfo -g | grep -q '$DOMAIN_GROUP' && id '${DOMAIN_USERS_PREFIX}1${DOMAIN_USERS_SUFFIX}' | grep -q '$DOMAIN_GROUP'" \
    "HQ-CLI domain join, winbind trust, or user lookup failed" \
    "check /etc/samba/smb.conf, /etc/krb5.conf, DNS and winbind"

  module2_guest_check "Limited sudo for hq group" "$HQ_CLI_VMID" \
    "visudo -cf /etc/sudoers.d/domain-hq-limited && sudo -l -U '${DOMAIN_USERS_PREFIX}1${DOMAIN_USERS_SUFFIX}' | grep -q '/usr/bin/id' && sudo -l -U '${DOMAIN_USERS_PREFIX}1${DOMAIN_USERS_SUFFIX}' | grep -q '/bin/cat' && sudo -l -U '${DOMAIN_USERS_PREFIX}1${DOMAIN_USERS_SUFFIX}' | grep -q '/bin/grep'" \
    "Limited sudo policy for hq group is missing or invalid" \
    "check /etc/sudoers.d/domain-hq-limited"

  echo
  if [[ "$module2_failed" -eq 0 ]]; then
    echo "RESULT: MODULE 2 PASSED"
  else
    echo "RESULT: MODULE 2 FAILED"
    return 1
  fi
}

print_module2_plan() {
  cat <<EOF

============================================================
MODULE 2 PLANNED STEPS
======================

[PLAN] 00-prereq.sh
  Implemented: verify Module 1 baseline, DNS, qemu-guest-agent, VLANs $VLAN_SRV/$VLAN_CLI/$VLAN_MGMT, SSH $SSH_PORT, HQ-CLI DHCP, and end-to-end reachability.
[RUN] 01-hq-srv-storage.sh
  RAID${RAID_LEVEL:-5} from ${RAID_DISK_COUNT:-3} x ${RAID_DISK_SIZE_GB:-1}GB disks on HQ-SRV, ${RAID_DEVICE:-/dev/md3}, mdadm.conf, ext4, mount ${RAID_MOUNT:-/raid}, NFS ${NFS_DIR:-/raid/nfs}, HQ-CLI automount ${NFS_CLIENT_MOUNT:-/mnt/nfs}.
[RUN] 02-hq-srv-nfs.sh
  NFS server on HQ-SRV exports ${NFS_DIR:-/raid/nfs} to ${HQ_CLI_NET:-192.168.213.0/27}; HQ-CLI mounts it at ${NFS_CLIENT_MOUNT:-/mnt/nfs}.
[RUN] 03-chrony.sh
  ISP chrony server with stratum ${NTP_STRATUM:-8}; HQ-SRV/HQ-CLI/BR-RTR/BR-SRV as clients.
[RUN] 04-br-srv-ansible.sh
  Ansible control node on BR-SRV in ${ANSIBLE_WORKDIR:-/etc/ansible}; inventory HQ-SRV/HQ-CLI/HQ-RTR/BR-RTR; ansible all -m ping check.
[RUN] Samba DC
  Samba DC on BR-SRV for ${DOMAIN:-au-team.irpo}/${REALM:-AU-TEAM.IRPO}, users ${DOMAIN_USERS_PREFIX:-hquser}1-${DOMAIN_USERS_PREFIX:-hquser}${DOMAIN_USERS_COUNT:-5}, group ${DOMAIN_GROUP:-hq}, sudo only cat/grep/id, HQ-CLI domain join.
[RUN] Docker/Web
  Docker on BR-SRV: images ${DOCKER_IMAGE_APP:-site_latest}/${DOCKER_IMAGE_DB:-postgresql_latest}, containers ${DOCKER_APP_CONTAINER:-site}/${DOCKER_DB_CONTAINER:-db}, DB ${DOCKER_DB_NAME:-testdb3}, user ${DOCKER_DB_USER:-test3c}, port ${DOCKER_APP_PORT:-8083}; Apache + MariaDB on HQ-SRV: DB ${WEB_DB_NAME:-webdb}, user ${WEB_DB_USER:-web3}, import dump.sql, copy index.php/images.
[RUN] DNAT/Proxy
  DNAT ${DOCKER_APP_PORT:-8083}: HQ-RTR -> HQ-SRV web, BR-RTR -> BR-SRV docker; DNAT ${SSH_PORT:-2013}: HQ-RTR -> HQ-SRV SSH, BR-RTR -> BR-SRV SSH; nginx reverse proxy on ISP: ${WEB_DOMAIN:-web.au-team.irpo} -> HQ-SRV web, ${DOCKER_DOMAIN:-docker.au-team.irpo} -> BR-SRV site.
[RUN] Basic auth / Browser
  Basic auth on ISP for ${WEB_DOMAIN:-web.au-team.irpo}: ${BASIC_AUTH_USER:-Kazimirc}, file ${BASIC_AUTH_FILE:-/etc/nginx/.htpasswd}; firewall rules after DNAT/proxy are confirmed.

All Module 2 blocks are automated in this revision; reruns are intended to be idempotent.
EOF
}

module2_step() {
  local label="$1"
  local command_text="$2"
  local hint="$3"
  shift 3

  echo
  echo "[STEP] $label"
  if "$@"; then
    echo "[OK] $label"
    return 0
  fi

  echo "[FAIL] $label"
  echo "Reason: block command failed"
  echo "Command: $command_text"
  echo "Next hint: $hint"
  return 1
}

demo_module2() {
  if [[ "$INVENTORY_LOADED" -ne 1 ]]; then
    ensure_demo_inventory
    load_inventory
  fi

  echo "============================================================"
  echo "MODULE 2 DEMO RUN"
  echo "============================================================"
  echo "This mode configures Module 2 blocks in safe order, then runs full checks."

  if ! module2_step "prereq module2" "bash run.sh prereq module2" "Run first: curl -fsSL https://raw.githubusercontent.com/Arsen11y/pve/main/m1.sh | bash" show_module2_prereq; then
    echo "RESULT: MODULE 2 DEMO BLOCKED"
    return 1
  fi
  if ! module2_step "run module2-storage" "bash run.sh run module2-storage" "check extra 1GB disks on HQ-SRV and rerun module2-storage" run_module2_storage; then
    echo "RESULT: MODULE 2 FAILED"
    return 1
  fi
  if ! module2_step "run module2-nfs" "bash run.sh run module2-nfs" "check RAID mount on HQ-SRV and network from HQ-CLI to HQ-SRV" run_module2_nfs; then
    echo "RESULT: MODULE 2 FAILED"
    return 1
  fi
  if ! module2_step "run module2-chrony" "bash run.sh run module2-chrony" "check chrony package availability and service name on ALT" run_module2_chrony; then
    echo "RESULT: MODULE 2 FAILED"
    return 1
  fi
  if ! module2_step "run module2-ansible" "bash run.sh run module2-ansible" "check ansible/sshpass packages and SSH reachability from BR-SRV" run_module2_ansible; then
    echo "RESULT: MODULE 2 FAILED"
    return 1
  fi
  if ! module2_step "run module2-docker" "bash run.sh run module2-docker" "check Additional.iso on BR-SRV and docker service" run_module2_docker; then
    echo "RESULT: MODULE 2 FAILED"
    return 1
  fi
  if ! module2_step "run module2-web" "bash run.sh run module2-web" "check Additional.iso on HQ-SRV and Apache/MariaDB packages" run_module2_web; then
    echo "RESULT: MODULE 2 FAILED"
    return 1
  fi
  if ! module2_step "run module2-dnat" "bash run.sh run module2-dnat" "check nftables on HQ-RTR/BR-RTR" run_module2_dnat; then
    echo "RESULT: MODULE 2 FAILED"
    return 1
  fi
  if ! module2_step "run module2-nginx" "bash run.sh run module2-nginx" "check nginx config and DNAT backends from ISP" run_module2_nginx; then
    echo "RESULT: MODULE 2 FAILED"
    return 1
  fi
  if ! module2_step "run module2-browser" "bash run.sh run module2-browser" "check Yandex Browser package availability on HQ-CLI" run_module2_browser; then
    echo "RESULT: MODULE 2 FAILED"
    return 1
  fi
  if ! module2_step "run module2-samba" "bash run.sh run module2-samba" "check Samba packages and domain DNS from BR-SRV/HQ-CLI" run_module2_samba; then
    echo "RESULT: MODULE 2 FAILED"
    return 1
  fi
  if ! module2_step "check module2" "bash run.sh check module2" "inspect failed check output above and rerun the failed block" show_module2_status; then
    echo "RESULT: MODULE 2 FAILED"
    return 1
  fi

  print_module2_plan
  echo
  echo "RESULT: MODULE 2 PASSED"
}

main() {
  need_root
  case "${1:-}" in
    check)
      case "${2:-}" in
        module1)
          show_module1_status
          ;;
        module2)
          show_module2_status
          ;;
        *)
          check_all
          ;;
      esac
      ;;
    list)
      qm list
      ;;
    demo)
      case "${2:-}" in
        module1)
          demo_module1
          ;;
        module2)
          demo_module2
          ;;
        *)
          usage
          exit 1
          ;;
      esac
      ;;
    prereq)
      case "${2:-}" in
        module2)
          show_module2_prereq
          ;;
        *)
          usage
          exit 1
          ;;
      esac
      ;;
    prepare-vlans)
      prepare_vlans
      ;;
    ifaces)
      show_ifaces "${2:-}"
      ;;
    status)
      if [[ "${2:-}" == "module1" ]]; then
        show_module1_status
      else
        show_status "${2:-}"
      fi
      ;;
    run)
      case "${2:-}" in
        module1)
          run_one isp
          run_one hq-rtr
          run_one br-rtr
          run_one hq-srv
          run_one br-srv
          run_one hq-cli
          ;;
        isp|hq-rtr|br-rtr|hq-srv|br-srv|hq-cli)
          run_one "$2"
          ;;
        module2-storage)
          run_module2_storage
          ;;
        module2-nfs)
          run_module2_nfs
          ;;
        module2-chrony)
          run_module2_chrony
          ;;
        module2-ansible)
          run_module2_ansible
          ;;
        module2-docker)
          run_module2_docker
          ;;
        module2-web)
          run_module2_web
          ;;
        module2-dnat)
          run_module2_dnat
          ;;
        module2-nginx)
          run_module2_nginx
          ;;
        module2-browser)
          run_module2_browser
          ;;
        module2-samba)
          run_module2_samba
          ;;
        module2)
          run_module2_all
          ;;
        *)
          usage
          exit 1
          ;;
      esac
      ;;
    *)
      usage
      ;;
  esac
}

main "$@"
