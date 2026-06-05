hostnamectl set-hostname HQ-RTR

cidr_ip() {
  printf '%s\n' "${1%%/*}"
}

write_eth_static "$HQ_RTR_WAN_IF" "$HQ_RTR_WAN_IP" "$HQ_RTR_WAN_GW"
cat > "/etc/net/ifaces/$HQ_RTR_WAN_IF/resolv.conf" <<EOFINNER
nameserver $DNS_FORWARDER_1
nameserver $DNS_FORWARDER_2
nameserver 8.8.8.8
EOFINNER
cat > /etc/resolv.conf <<EOFINNER
nameserver $DNS_FORWARDER_1
nameserver $DNS_FORWARDER_2
nameserver 8.8.8.8
EOFINNER
restart_network_safe
ip -br a || true
ip route || true
ping -c 4 "$HQ_RTR_WAN_GW" || true

safe_apt_install nftables sudo dhcp-server frr tzdata
timedatectl set-timezone "$TZ"

id "$ROUTER_ADMIN_USER" >/dev/null 2>&1 || useradd -m -s /bin/bash "$ROUTER_ADMIN_USER"
echo "$ROUTER_ADMIN_USER:$ROUTER_ADMIN_PASS" | chpasswd
mkdir -p /etc/sudoers.d
echo "$ROUTER_ADMIN_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$ROUTER_ADMIN_USER"
chmod 440 "/etc/sudoers.d/$ROUTER_ADMIN_USER"

ensure_iface_dir "$HQ_RTR_LAN_IF"
cat > "/etc/net/ifaces/$HQ_RTR_LAN_IF/options" <<EOFINNER
TYPE=eth
EOFINNER
rm -f "/etc/net/ifaces/$HQ_RTR_LAN_IF/ipv4address" "/etc/net/ifaces/$HQ_RTR_LAN_IF/ipv4route"

for vid in "$VLAN_SRV" "$VLAN_CLI" "$VLAN_MGMT"; do
  ensure_iface_dir "$HQ_RTR_LAN_IF.$vid"
done

cat > "/etc/net/ifaces/$HQ_RTR_LAN_IF.$VLAN_SRV/options" <<EOFINNER
TYPE=vlan
HOST=$HQ_RTR_LAN_IF
VID=$VLAN_SRV
BOOTPROTO=static
EOFINNER
cat > "/etc/net/ifaces/$HQ_RTR_LAN_IF.$VLAN_CLI/options" <<EOFINNER
TYPE=vlan
HOST=$HQ_RTR_LAN_IF
VID=$VLAN_CLI
BOOTPROTO=static
EOFINNER
cat > "/etc/net/ifaces/$HQ_RTR_LAN_IF.$VLAN_MGMT/options" <<EOFINNER
TYPE=vlan
HOST=$HQ_RTR_LAN_IF
VID=$VLAN_MGMT
BOOTPROTO=static
EOFINNER

echo "$HQ_RTR_SRV_GW" > "/etc/net/ifaces/$HQ_RTR_LAN_IF.$VLAN_SRV/ipv4address"
echo "$HQ_RTR_CLI_GW" > "/etc/net/ifaces/$HQ_RTR_LAN_IF.$VLAN_CLI/ipv4address"
echo "$HQ_RTR_MGMT_GW" > "/etc/net/ifaces/$HQ_RTR_LAN_IF.$VLAN_MGMT/ipv4address"

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

mkdir -p /etc/dhcp /etc/sysconfig
cat > /etc/dhcp/dhcpd.conf <<EOFINNER
authoritative;
option domain-name "$DOMAIN";
option domain-name-servers $HQ_SRV_ADDR;
default-lease-time 600;
max-lease-time 7200;

subnet ${HQ_CLI_NET%/*} netmask 255.255.255.224 {
  range $HQ_CLI_DHCP_START $HQ_CLI_DHCP_END;
  option routers $HQ_RTR_CLI_ADDR;
  option domain-name "$DOMAIN";
  option domain-name-servers $HQ_SRV_ADDR;
}
EOFINNER
cat > /etc/sysconfig/dhcpd <<EOFINNER
DHCPDARGS="$HQ_RTR_LAN_IF.$VLAN_CLI"
INTERFACES="$HQ_RTR_LAN_IF.$VLAN_CLI"
DHCPD_IFACE="$HQ_RTR_LAN_IF.$VLAN_CLI"
EOFINNER

mkdir -p /etc/frr
touch /etc/frr/daemons
grep -q '^zebra=' /etc/frr/daemons && sed -i 's/^zebra=.*/zebra=yes/' /etc/frr/daemons || echo 'zebra=yes' >> /etc/frr/daemons
grep -q '^ospfd=' /etc/frr/daemons && sed -i 's/^ospfd=.*/ospfd=yes/' /etc/frr/daemons || echo 'ospfd=yes' >> /etc/frr/daemons
cat > /etc/frr/frr.conf <<EOFINNER
frr version 9.0
frr defaults traditional
hostname HQ-RTR
log syslog informational
service integrated-vtysh-config

interface gre1
 ip ospf network point-to-point
 ip ospf mtu-ignore

router ospf
 ospf router-id 1.1.1.1
 network 10.10.10.0/30 area 0
 network $HQ_SRV_NET area 0
 network $HQ_CLI_NET area 0
 network $MGMT_NET area 0
EOFINNER
chown frr:frr /etc/frr/frr.conf /etc/frr/daemons 2>/dev/null || true
chmod 640 /etc/frr/frr.conf 2>/dev/null || true

cat > /etc/systemd/system/gre1-demo.service <<EOFINNER
[Unit]
Description=GRE tunnel gre1 for demo exam
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=/bin/sh -c 'ip link set gre1 down 2>/dev/null || true'
ExecStartPre=/bin/sh -c 'ip tunnel del gre1 2>/dev/null || true'
ExecStart=/bin/sh -c 'ip tunnel add gre1 mode gre local $HQ_RTR_WAN_ADDR remote $BR_RTR_WAN_ADDR ttl 255'
ExecStart=/bin/sh -c 'ip addr add 10.10.10.1/30 dev gre1'
ExecStart=/bin/sh -c 'ip link set gre1 up multicast on'
ExecStart=/bin/sh -c 'ip route replace 10.10.10.0/30 dev gre1'
ExecStart=/bin/sh -c 'ip route replace 224.0.0.0/4 dev gre1'
ExecStop=/bin/sh -c 'ip link set gre1 down 2>/dev/null || true; ip tunnel del gre1 2>/dev/null || true'

[Install]
WantedBy=multi-user.target
EOFINNER

systemctl enable nftables
restart_network_safe
systemctl restart nftables

dhcp_service_started=0
for svc in dhcpd dhcp-server; do
  if systemctl cat "$svc" >/dev/null 2>&1; then
    systemctl enable "$svc"
    systemctl restart "$svc"
    dhcp_service_started=1
    break
  fi
done
[[ "$dhcp_service_started" -eq 1 ]] || echo "WARNING: DHCP service unit not found"

systemctl daemon-reload
systemctl enable gre1-demo.service
systemctl restart gre1-demo.service
systemctl enable frr
systemctl restart frr

ip -br a || true
ip tunnel show gre1 || true
ping -c 4 10.10.10.2 || true
vtysh -c 'show ip ospf neighbor' || true
vtysh -c 'show ip route ospf' || true
