#!/usr/bin/env bash
set -euo pipefail

DEFAULT_DE_RAW_URL="https://raw.githubusercontent.com/Arsen11y/pve/main/proxmox-remote"
DE_RAW_URL="${DE_RAW_URL:-$DEFAULT_DE_RAW_URL}"
INV="${DE_INVENTORY:-/root/de-inventory.env}"
RUNNER="/tmp/de-run.sh"

curl_raw_to_file() {
  local url="$1"
  local dest="$2"
  local label="$3"
  local expected="${4:-}"
  local tmp
  tmp="${dest}.tmp"
  if ! curl --retry 5 --retry-delay 2 --retry-all-errors --connect-timeout 20 --max-time 120 -fSL "$url" > "$tmp"; then
    echo "[FAIL] failed to download $label"
    echo "URL: $url"
    echo "Retry: curl -fsSL https://raw.githubusercontent.com/Arsen11y/pve/main/m1.sh | bash"
    rm -f "$tmp"
    exit 1
  fi
  if [[ ! -s "$tmp" ]] || head -n 5 "$tmp" | grep -Eqi '<html|<!doctype|404:|not found|rate limit|error'; then
    echo "[FAIL] downloaded $label is empty or invalid"
    echo "URL: $url"
    echo "Retry: curl -fsSL https://raw.githubusercontent.com/Arsen11y/pve/main/m1.sh | bash"
    rm -f "$tmp"
    exit 1
  fi
  if [[ -n "$expected" ]] && ! grep -q "$expected" "$tmp"; then
    echo "[FAIL] downloaded $label does not contain expected marker: $expected"
    echo "URL: $url"
    echo "Retry: curl -fsSL https://raw.githubusercontent.com/Arsen11y/pve/main/m1.sh | bash"
    rm -f "$tmp"
    exit 1
  fi
  mv "$tmp" "$dest"
}

echo "[STEP] refresh inventory"
mkdir -p "$(dirname "$INV")"
if [[ -f "$INV" ]]; then
  ts="$(date +%Y%m%d-%H%M%S)"
  cp "$INV" "$INV.bak.$ts"
  echo "[OK] inventory backup: $INV.bak.$ts"
fi
curl_raw_to_file "$DE_RAW_URL/inventory.example.env" "$INV" "inventory.example.env" "ISP_VMID="
echo "[OK] inventory refreshed: $INV"

curl_raw_to_file "$DE_RAW_URL/run.sh" "$RUNNER" "run.sh" "guest_exec_pretty"
DE_RAW_URL="$DE_RAW_URL" bash "$RUNNER" demo module1
