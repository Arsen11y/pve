hostnamectl set-hostname BR-RTR

safe_apt_install nftables tzdata
timedatectl set-timezone "$TZ"

write_eth_static "$BR_RTR_WAN_IF" "$BR_RTR_WAN_IP" "$BR_RTR_WAN_GW"
write_eth_static "$BR_RTR_LAN_IF" "$BR_RTR_LAN_IP"

enable_ip_forward

mkdir -p /etc/nftables
cat > /etc/nftables/nftables.nft <<EOFINNER
#!/usr/sbin/nft -f
flush ruleset

table ip nat {
    chain postrouting {
        type nat hook postrouting priority srcnat;
        oifname "$BR_RTR_WAN_IF" masquerade
    }
}
EOFINNER

systemctl enable --now nftables
restart_network_safe
systemctl restart nftables

basic_check
nft list ruleset
