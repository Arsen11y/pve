hostnamectl set-hostname BR-RTR

write_eth_static "$BR_RTR_WAN_IF" "$BR_RTR_WAN_IP" "$BR_RTR_WAN_GW"
cat > "/etc/net/ifaces/$BR_RTR_WAN_IF/resolv.conf" <<EOFINNER
nameserver 8.8.8.8
nameserver 1.1.1.1
nameserver 77.88.8.8
EOFINNER
cat > /etc/resolv.conf <<EOFINNER
nameserver 8.8.8.8
nameserver 1.1.1.1
nameserver 77.88.8.8
EOFINNER
restart_network_safe
ip -br a || true
ip route || true
ping -c 4 "$BR_RTR_WAN_GW" || true

safe_apt_install nftables sudo frr tzdata
timedatectl set-timezone "$TZ"

id "$NET_ADMIN_USER" >/dev/null 2>&1 || useradd -m -s /bin/bash "$NET_ADMIN_USER"
echo "$NET_ADMIN_USER:$DEMO_PASS" | chpasswd
mkdir -p /etc/sudoers.d
echo "$NET_ADMIN_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$NET_ADMIN_USER"
chmod 440 "/etc/sudoers.d/$NET_ADMIN_USER"

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

mkdir -p /etc/frr
touch /etc/frr/daemons
grep -q '^zebra=' /etc/frr/daemons && sed -i 's/^zebra=.*/zebra=yes/' /etc/frr/daemons || echo 'zebra=yes' >> /etc/frr/daemons
grep -q '^ospfd=' /etc/frr/daemons && sed -i 's/^ospfd=.*/ospfd=yes/' /etc/frr/daemons || echo 'ospfd=yes' >> /etc/frr/daemons
cat > /etc/frr/frr.conf <<EOFINNER
frr version 9.0
frr defaults traditional
hostname BR-RTR
log syslog informational
service integrated-vtysh-config

interface gre1
 ip ospf network point-to-point
 ip ospf mtu-ignore

router ospf
 ospf router-id 2.2.2.2
 network 10.10.10.0/30 area 0
 network 192.168.10.0/28 area 0
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
ExecStart=/bin/sh -c 'ip tunnel add gre1 mode gre local 172.16.2.2 remote 172.16.1.2 ttl 255'
ExecStart=/bin/sh -c 'ip addr add 10.10.10.2/30 dev gre1'
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

systemctl daemon-reload
systemctl enable gre1-demo.service
systemctl restart gre1-demo.service
systemctl enable frr
systemctl restart frr

ip -br a || true
ip tunnel show gre1 || true
ping -c 4 10.10.10.1 || true
vtysh -c 'show ip ospf neighbor' || true
vtysh -c 'show ip route ospf' || true
