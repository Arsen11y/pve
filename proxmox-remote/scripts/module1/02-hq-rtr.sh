hostnamectl set-hostname HQ-RTR

# Пакет vlan не ставим: в ALT он может отсутствовать.
safe_apt_install nftables tzdata
timedatectl set-timezone "$TZ"

write_eth_static "$HQ_RTR_WAN_IF" "$HQ_RTR_WAN_IP" "$HQ_RTR_WAN_GW"

ensure_iface_dir "$HQ_RTR_LAN_IF"
cat > "/etc/net/ifaces/$HQ_RTR_LAN_IF/options" <<EOFINNER
TYPE=eth
EOFINNER

for vid in 100 200 999; do
  ensure_iface_dir "$HQ_RTR_LAN_IF.$vid"
done

cat > "/etc/net/ifaces/$HQ_RTR_LAN_IF.100/options" <<EOFINNER
TYPE=vlan
HOST=$HQ_RTR_LAN_IF
VID=100
EOFINNER
cat > "/etc/net/ifaces/$HQ_RTR_LAN_IF.200/options" <<EOFINNER
TYPE=vlan
HOST=$HQ_RTR_LAN_IF
VID=200
EOFINNER
cat > "/etc/net/ifaces/$HQ_RTR_LAN_IF.999/options" <<EOFINNER
TYPE=vlan
HOST=$HQ_RTR_LAN_IF
VID=999
EOFINNER

echo "$HQ_RTR_VLAN100_IP" > "/etc/net/ifaces/$HQ_RTR_LAN_IF.100/ipv4address"
echo "$HQ_RTR_VLAN200_IP" > "/etc/net/ifaces/$HQ_RTR_LAN_IF.200/ipv4address"
echo "$HQ_RTR_VLAN999_IP" > "/etc/net/ifaces/$HQ_RTR_LAN_IF.999/ipv4address"

enable_ip_forward

mkdir -p /etc/nftables
cat > /etc/nftables/nftables.nft <<EOFINNER
#!/usr/sbin/nft -f
flush ruleset

table ip nat {
    chain postrouting {
        type nat hook postrouting priority srcnat;
        oifname "$HQ_RTR_WAN_IF" masquerade
    }
}
EOFINNER

systemctl enable --now nftables
restart_network_safe
systemctl restart nftables

basic_check
nft list ruleset
