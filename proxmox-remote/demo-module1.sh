#!/usr/bin/env bash
set -euo pipefail

DEFAULT_DE_RAW_URL="https://raw.githubusercontent.com/Arsen11y/pve/module1-only/proxmox-remote"
DE_RAW_URL="${DE_RAW_URL:-$DEFAULT_DE_RAW_URL}"
INV="${DE_INVENTORY:-/root/de-inventory.env}"

echo "DE_RAW_URL=$DE_RAW_URL"
echo "INVENTORY=$INV"

if [[ ! -f "$INV" ]]; then
  echo "[STEP] create inventory: $INV"
  mkdir -p "$(dirname "$INV")"
  curl -fsSL "$DE_RAW_URL/inventory.example.env" > "$INV"
  echo "[OK] inventory created"
else
  echo "[OK] inventory exists: $INV"
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

curl -fsSL "$DE_RAW_URL/run.sh" > "$tmpdir/run.sh"
bash "$tmpdir/run.sh" demo module1
