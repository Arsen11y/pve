#!/usr/bin/env bash
set -euo pipefail

DEFAULT_DE_RAW_URL="https://raw.githubusercontent.com/Arsen11y/pve/main/proxmox-remote"
DE_RAW_URL="${DE_RAW_URL:-$DEFAULT_DE_RAW_URL}"
INV="${DE_INVENTORY:-/root/de-inventory.env}"
RUNNER="/tmp/de-run.sh"

echo "[STEP] refresh inventory"
mkdir -p "$(dirname "$INV")"
curl -fsSL "$DE_RAW_URL/inventory.example.env" > "$INV"
echo "[OK] inventory refreshed: $INV"

curl -fsSL "$DE_RAW_URL/run.sh" > "$RUNNER"
DE_RAW_URL="$DE_RAW_URL" bash "$RUNNER" demo module2
