#!/usr/bin/env bash
set -euo pipefail

# run.sh вЂ” СѓРґР°Р»С‘РЅРЅС‹Р№ Р·Р°РїСѓСЃРє СЃ GitHub Р±РµР· РєР»РѕРЅРёСЂРѕРІР°РЅРёСЏ СЂРµРїРѕР·РёС‚РѕСЂРёСЏ.
#
# РџСЂРёРјРµСЂ:
# export DE_RAW_URL="https://raw.githubusercontent.com/Arsen11y/PVE/main/proxmox-remote"
# curl -fsSL "$DE_RAW_URL/run.sh" | DE_RAW_URL="$DE_RAW_URL" bash -s -- check
# curl -fsSL "$DE_RAW_URL/run.sh" | DE_RAW_URL="$DE_RAW_URL" bash -s -- run isp

DEFAULT_RAW_URL="https://raw.githubusercontent.com/Arsen11y/PVE/main/proxmox-remote"
DE_RAW_URL="${DE_RAW_URL:-$DEFAULT_RAW_URL}"
INV="${DE_INVENTORY:-/root/de-inventory.env}"

if [[ -f "$INV" ]]; then
  # shellcheck disable=SC1090
  source "$INV"
else
  echo "РќРµ РЅР°Р№РґРµРЅ inventory: $INV"
  echo "РЎРѕР·РґР°Р№ РµРіРѕ РєРѕРјР°РЅРґРѕР№:"
  echo "curl -fsSL \"$DE_RAW_URL/inventory.example.env\" > /root/de-inventory.env"
  echo "nano /root/de-inventory.env"
  exit 1
fi

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Р—Р°РїСѓСЃС‚Рё РѕС‚ root РЅР° Proxmox."
    exit 1
  fi
}

usage() {
  cat <<'EOF'
run.sh вЂ” СѓРґР°Р»С‘РЅРЅС‹Р№ Р·Р°РїСѓСЃРє РєРѕРјР°РЅРґ Р”Р­ С‡РµСЂРµР· Proxmox qemu-guest-agent.

РљРѕРјР°РЅРґС‹:
  check                 РџСЂРѕРІРµСЂРёС‚СЊ РЅР°Р»РёС‡РёРµ Р’Рњ Рё qemu-guest-agent
  list                  РџРѕРєР°Р·Р°С‚СЊ qm list
  ifaces <target>       РџРѕРєР°Р·Р°С‚СЊ ip -br a РІРЅСѓС‚СЂРё Р’Рњ
  status <target>       РљРѕСЂРѕС‚РєРёР№ СЃС‚Р°С‚СѓСЃ Р’Рњ: hostname, ip, route
  run <target>          Р—Р°РїСѓСЃС‚РёС‚СЊ РЅР°СЃС‚СЂРѕР№РєСѓ СѓР·Р»Р°

Targets:
  isp
  hq-rtr
  br-rtr
  hq-srv
  br-srv
  hq-cli
  module1

РџСЂРёРјРµСЂС‹:
  curl -fsSL "$DE_RAW_URL/run.sh" | DE_RAW_URL="$DE_RAW_URL" bash -s -- check
  curl -fsSL "$DE_RAW_URL/run.sh" | DE_RAW_URL="$DE_RAW_URL" bash -s -- ifaces isp
  curl -fsSL "$DE_RAW_URL/run.sh" | DE_RAW_URL="$DE_RAW_URL" bash -s -- run isp
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
    echo "РћРЁРР‘РљРђ: Р’Рњ РґР»СЏ target='$target' СЃ VMID=$vmid РЅРµ РЅР°Р№РґРµРЅР°."
    echo
    echo "РЎРµР№С‡Р°СЃ РЅР° Proxmox РµСЃС‚СЊ:"
    qm list || true
    echo
    echo "РСЃРїСЂР°РІСЊ VMID РІ $INV"
    exit 1
  fi
}

guest_ping() {
  local vmid="$1"
  qm agent "$vmid" ping >/dev/null 2>&1
}

guest_exec_lc() {
  local vmid="$1"
  local cmd="$2"
  qm guest exec "$vmid" -- bash -lc "$cmd"
}

fetch() {
  local rel="$1"
  curl -fsSL "$DE_RAW_URL/$rel"
}

run_one() {
  local target="$1"
  local vmid
  local script_rel

  vmid="$(target_vmid "$target")"
  script_rel="$(target_script "$target")"

  require_vm "$target" "$vmid"

  echo
  echo "============================================================"
  echo "TARGET=$target VMID=$vmid SCRIPT=$script_rel"
  echo "============================================================"

  if ! guest_ping "$vmid"; then
    echo "РћРЁРР‘РљРђ: qemu-guest-agent РЅРµ РѕС‚РІРµС‡Р°РµС‚ РІ VMID=$vmid ($target)."
    echo "РџСЂРѕРІРµСЂСЊ РІРЅСѓС‚СЂРё Р’Рњ: apt-get install -y qemu-guest-agent && systemctl enable --now qemu-guest-agent"
    exit 1
  fi

  {
    echo "set -euo pipefail"
    echo "cat > /tmp/de_inventory.env <<'EOF_INV'"
    cat "$INV"
    echo "EOF_INV"
    echo "source /tmp/de_inventory.env"
    fetch "scripts/lib/common.sh"
    echo
    fetch "$script_rel"
  } | qm guest exec "$vmid" -- bash -s
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
  guest_exec_lc "$vmid" "ip -br a"
}

show_status() {
  local target="$1"
  local vmid
  vmid="$(target_vmid "$target")"
  require_vm "$target" "$vmid"
  guest_exec_lc "$vmid" "hostname; echo '--- ip ---'; ip -br a; echo '--- route ---'; ip route"
}

main() {
  need_root
  case "${1:-}" in
    check)
      check_all
      ;;
    list)
      qm list
      ;;
    ifaces)
      show_ifaces "${2:-}"
      ;;
    status)
      show_status "${2:-}"
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

