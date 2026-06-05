#!/usr/bin/env bash
set -euo pipefail

DEFAULT_RAW_URL="https://raw.githubusercontent.com/Arsen11y/pve/module1-only/proxmox-remote"
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
  return 1
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

if [[ ! ( "$REQUEST_COMMAND" == "demo" && "$REQUEST_SUBCOMMAND" == "module1" ) ]]; then
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
  demo module1             Prepare VLANs, run all Module 1 targets, then check
  prepare-vlans            Add/replace Proxmox VLAN tags for HQ-SRV/HQ-CLI
  list                     Show qm list
  ifaces <target>          Show ip -br a inside VM
  status <target>          Show hostname, ip and routes inside VM
  status module1           Same as check module1
  run <target>             Run target configuration

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
  mkdir -p "$tmpdir/scripts/lib" "$tmpdir/scripts/module1"
  cp "$INV" "$tmpdir/de-inventory.env"
  fetch "scripts/lib/common.sh" > "$tmpdir/scripts/lib/common.sh"
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

main() {
  need_root
  case "${1:-}" in
    check)
      case "${2:-}" in
        module1)
          show_module1_status
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
