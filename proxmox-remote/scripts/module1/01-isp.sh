hostnamectl set-hostname ISP

write_eth_dhcp "$ISP_WAN_IF"
write_eth_static "$ISP_HQ_IF" "$ISP_HQ_IP"
write_eth_static "$ISP_BR_IF" "$ISP_BR_IP"

safe_apt_install nftables tzdata
timedatectl set-timezone "$TZ"

enable_ip_forward

mkdir -p /etc/nftables
cat > /etc/nftables/nftables.nft <<EOFINNER
#!/usr/sbin/nft -f
flush ruleset

table ip nat {
    chain postrouting {
        type nat hook postrouting priority srcnat;
        oifname "$ISP_WAN_IF" masquerade
    }
}
EOFINNER

systemctl enable nftables
restart_network_safe
systemctl restart nftables

hostname || true
ip -br a || true
ip route || true
cat /proc/sys/net/ipv4/ip_forward || true
nft list ruleset || true
ping -c 4 8.8.8.8 || true
