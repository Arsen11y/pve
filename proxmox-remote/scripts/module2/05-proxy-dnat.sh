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

write_router_nat() {
  local wan_if="$1"
  local wan_addr="$2"
  local web_target="$3"
  local ssh_target="$4"

  enable_ip_forward
  mkdir -p /etc/nftables
  cat > /etc/nftables/nftables.nft <<EOFINNER
#!/usr/sbin/nft -f
flush ruleset

table ip nat {
    chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;
        iifname "$wan_if" ip daddr $wan_addr tcp dport $SSH_PORT dnat to $ssh_target
        iifname "$wan_if" ip daddr $wan_addr tcp dport $DOCKER_APP_PORT dnat to $web_target
    }

    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        oifname "$wan_if" masquerade
    }
}
EOFINNER
  systemctl enable nftables
  systemctl restart nftables
  nft list ruleset
}

host="$(hostname | tr '[:upper:]' '[:lower:]')"
case "$host" in
  hq-rtr*)
    write_router_nat "$HQ_RTR_WAN_IF" "$HQ_RTR_WAN_ADDR" "$HQ_SRV_ADDR:80" "$HQ_SRV_ADDR:$SSH_PORT"
    echo "[OK] HQ-RTR DNAT configured"
    ;;
  br-rtr*)
    write_router_nat "$BR_RTR_WAN_IF" "$BR_RTR_WAN_ADDR" "$BR_SRV_ADDR:$DOCKER_APP_PORT" "$BR_SRV_ADDR:$SSH_PORT"
    echo "[OK] BR-RTR DNAT configured"
    ;;
  *)
    echo "[FAIL] Unsupported DNAT target host: $host"
    echo "Command: hostname"
    echo "Next hint: run module2-dnat only on HQ-RTR and BR-RTR"
    exit 1
    ;;
esac
