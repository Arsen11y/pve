#!/usr/bin/env bash
set -euo pipefail

# run.sh — удалённый запуск с GitHub без клонирования репозитория.
# Пример:
# DE_RAW_URL="https://raw.githubusercontent.com/OWNER/REPO/main/proxmox-remote" \
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/OWNER/REPO/main/proxmox-remote/run.sh)" -- check

DEFAULT_RAW_URL="https://raw.githubusercontent.com/OWNER/REPO/main/proxmox-remote"
DE_RAW_URL="${DE_RAW_URL:-$DEFAULT_RAW_URL}"
INV_FILE="${DE_INVENTORY:-/root/de-inventory.env}"
TMP_DIR="/tmp/de-remote-runner"

usage() {
  cat <<EOFUSAGE
Удалённый запуск ДЭ-команд через Proxmox/qemu-guest-agent.

Команды:
  check                 проверить VMID и qemu-guest-agent
  print-inventory       вывести шаблон inventory.env
  ifaces <target>       показать ip -br a внутри ВМ
  status <target>       показать hostname/ip/route внутри ВМ
  run <target>          запустить настройку цели
  run module1           запустить ISP, HQ-RTR, BR-RTR, HQ-SRV, BR-SRV, HQ-CLI

Цели:
  isp | hq-rtr | br-rtr | hq-srv | br-srv | hq-cli | module1

Переменные:
  DE_RAW_URL            raw URL папки proxmox-remote в GitHub
  DE_INVENTORY          путь к inventory.env, по умолчанию /root/de-inventory.env

Первый запуск:
  curl -fsSL "$DE_RAW_URL/inventory.example.env" > /root/de-inventory.env
  nano /root/de-inventory.env
  curl -fsSL "$DE_RAW_URL/run.sh" | DE_RAW_URL="$DE_RAW_URL" bash -s -- check

EOFUSAGE
}

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Запусти от root на Proxmox."
    exit 1
  fi
}

fetch() {
  local remote_path="$1"
  local local_path="$2"
  mkdir -p "$(dirname "$local_path")"
  curl -fsSL "$DE_RAW_URL/$remote_path" -o "$local_path"
}

prepare_tmp() {
  rm -rf "$TMP_DIR"
  mkdir -p "$TMP_DIR/scripts/lib" "$TMP_DIR/scripts/module1"
  fetch "scripts/lib/common.sh" "$TMP_DIR/scripts/lib/common.sh"
  for f in 01-isp.sh 02-hq-rtr.sh 03-br-rtr.sh 04-hq-srv.sh 05-br-srv.sh 06-hq-cli.sh; do
    fetch "scripts/module1/$f" "$TMP_DIR/scripts/module1/$f"
  done
}

load_inventory() {
  if [[ ! -f "$INV_FILE" ]]; then
    echo "Не найден inventory: $INV_FILE"
    echo "Создай его командой:"
    echo "curl -fsSL '$DE_RAW_URL/inventory.example.env' > $INV_FILE"
    exit 1
  fi
  # shellcheck disable=SC1090
  source "$INV_FILE"
}

vmid_for_target() {
  case "$1" in
    isp) echo "$ISP_VMID" ;;
    hq-rtr) echo "$HQ_RTR_VMID" ;;
    br-rtr) echo "$BR_RTR_VMID" ;;
    hq-srv) echo "$HQ_SRV_VMID" ;;
    br-srv) echo "$BR_SRV_VMID" ;;
    hq-cli) echo "$HQ_CLI_VMID" ;;
    *) echo "" ;;
  esac
}

script_for_target() {
  case "$1" in
    isp) echo "$TMP_DIR/scripts/module1/01-isp.sh" ;;
    hq-rtr) echo "$TMP_DIR/scripts/module1/02-hq-rtr.sh" ;;
    br-rtr) echo "$TMP_DIR/scripts/module1/03-br-rtr.sh" ;;
    hq-srv) echo "$TMP_DIR/scripts/module1/04-hq-srv.sh" ;;
    br-srv) echo "$TMP_DIR/scripts/module1/05-br-srv.sh" ;;
    hq-cli) echo "$TMP_DIR/scripts/module1/06-hq-cli.sh" ;;
    *) echo "" ;;
  esac
}

guest_exec_script() {
  local target="$1"
  local vmid
  local script
  vmid="$(vmid_for_target "$target")"
  script="$(script_for_target "$target")"

  if [[ -z "$vmid" || -z "$script" || ! -f "$script" ]]; then
    echo "Неизвестная цель: $target"
    exit 1
  fi

  echo
  echo "============================================================"
  echo "TARGET=$target VMID=$vmid"
  echo "============================================================"

  qm agent "$vmid" ping >/dev/null

  {
    echo 'set -euo pipefail'
    echo "cat > /tmp/de_inventory.env <<'EOFINVENTORY'"
    cat "$INV_FILE"
    echo "EOFINVENTORY"
    echo 'source /tmp/de_inventory.env'
    echo "cat > /tmp/de_common.sh <<'EOFCOMMON'"
    cat "$TMP_DIR/scripts/lib/common.sh"
    echo "EOFCOMMON"
    echo 'source /tmp/de_common.sh'
    cat "$script"
  } | qm guest exec "$vmid" -- bash -s
}

check() {
  echo "Proxmox VM list:"
  qm list
  echo
  for target in isp hq-rtr br-rtr hq-srv br-srv hq-cli; do
    local vmid
    vmid="$(vmid_for_target "$target")"
    printf "%-7s VMID=%s ... " "$target" "$vmid"
    if qm agent "$vmid" ping >/dev/null 2>&1; then
      echo OK
    else
      echo FAIL
    fi
  done
}

show_guest() {
  local target="$1"
  local mode="$2"
  local vmid
  vmid="$(vmid_for_target "$target")"
  if [[ -z "$vmid" ]]; then
    echo "Неизвестная цель: $target"
    exit 1
  fi
  if [[ "$mode" == "ifaces" ]]; then
    qm guest exec "$vmid" -- bash -lc "ip -br a"
  else
    qm guest exec "$vmid" -- bash -lc "hostname; ip -br a; ip route; systemctl is-active qemu-guest-agent || true"
  fi
}

main() {
  need_root

  if [[ "${1:-}" == "print-inventory" ]]; then
    curl -fsSL "$DE_RAW_URL/inventory.example.env"
    exit 0
  fi

  load_inventory
  prepare_tmp

  case "${1:-}" in
    check)
      check
      ;;
    ifaces)
      show_guest "${2:-}" ifaces
      ;;
    status)
      show_guest "${2:-}" status
      ;;
    run)
      case "${2:-}" in
        module1)
          for target in isp hq-rtr br-rtr hq-srv br-srv hq-cli; do
            guest_exec_script "$target"
          done
          ;;
        isp|hq-rtr|br-rtr|hq-srv|br-srv|hq-cli)
          guest_exec_script "$2"
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
