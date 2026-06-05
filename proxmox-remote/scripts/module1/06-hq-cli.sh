hostnamectl set-hostname HQ-CLI

write_eth_dhcp "$HQ_CLI_IF"

pkill dhcpcd 2>/dev/null || true
rm -f "/run/dhcpcd/$HQ_CLI_IF.pid"
ip addr flush dev "$HQ_CLI_IF" || true
restart_network_safe

safe_apt_install tzdata bind-utils
timedatectl set-timezone "$TZ"

ip -br a || true
ip route || true
cat /etc/resolv.conf || true
ping -c 4 "$HQ_RTR_CLI_ADDR" || true
ping -c 4 "$BR_SRV_ADDR" || true
nslookup "hq-srv.$DOMAIN" "$HQ_SRV_ADDR" || true
