hostnamectl set-hostname HQ-RTR

safe_apt_install nftables sudo dhcp-server frr tzdata
timedatectl set-timezone "$TZ"

id "$NET_ADMIN_USER" >/dev/null 2>&1 || useradd -m -s /bin/bash "$NET_ADMIN_USER"
echo "$NET_ADMIN_USER:$DEMO_PASS" | chpasswd
mkdir -p /etc/sudoers.d
echo "$NET_ADMIN_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$NET_ADMIN_USER"
chmod 440 "/etc/sudoers.d/$NET_ADMIN_USER"

write_eth_static "$HQ_RTR_WAN_IF" "$HQ_RTR_WAN_IP" "$HQ_RTR_WAN_GW"

ensure_iface_dir "$HQ_RTR_LAN_IF"
cat > "/etc/net/ifaces/$HQ_RTR_LAN_IF/options" <<EOFINNER
TYPE=eth
EOFINNER
rm -f "/etc/net/ifaces/$HQ_RTR_LAN_IF/ipv4address" "/etc/net/ifaces/$HQ_RTR_LAN_IF/ipv4route"

for vid in 100 200 999; do
  ensure_iface_dir "$HQ_RTR_LAN_IF.$vid"
done

cat > "/etc/net/ifaces/$HQ_RTR_LAN_IF.100/options" <<EOFINNER
TYPE=vlan
HOST=$HQ_RTR_LAN_IF
VID=100
BOOTPROTO=static
EOFINNER
cat > "/etc/net/ifaces/$HQ_RTR_LAN_IF.200/options" <<EOFINNER
TYPE=vlan
HOST=$HQ_RTR_LAN_IF
VID=200
BOOTPROTO=static
EOFINNER
cat > "/etc/net/ifaces/$HQ_RTR_LAN_IF.999/options" <<EOFINNER
TYPE=vlan
HOST=$HQ_RTR_LAN_IF
VID=999
BOOTPROTO=static
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

mkdir -p /etc/dhcp /etc/sysconfig
cat > /etc/dhcp/dhcpd.conf <<EOFINNER
authoritative;
option domain-name "$DOMAIN";
option domain-name-servers 192.168.100.2;
default-lease-time 600;
max-lease-time 7200;

subnet 192.168.200.0 netmask 255.255.255.224 {
  range 192.168.200.10 192.168.200.30;
  option routers 192.168.200.1;
  option domain-name "$DOMAIN";
  option domain-name-servers 192.168.100.2;
}
EOFINNER
cat > /etc/sysconfig/dhcpd <<EOFINNER
DHCPDARGS="$HQ_RTR_LAN_IF.200"
INTERFACES="$HQ_RTR_LAN_IF.200"
DHCPD_IFACE="$HQ_RTR_LAN_IF.200"
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
 network 192.168.100.0/27 area 0
 network 192.168.200.0/27 area 0
 network 192.168.99.0/29 area 0
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
ExecStart=/bin/sh -c 'ip tunnel add gre1 mode gre local 172.16.1.2 remote 172.16.2.2 ttl 255'
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
