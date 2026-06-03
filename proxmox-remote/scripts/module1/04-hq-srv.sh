hostnamectl set-hostname HQ-SRV

write_eth_static "$HQ_SRV_IF" "$HQ_SRV_IP" "$HQ_SRV_GW"
echo "search $DOMAIN" > "/etc/net/ifaces/$HQ_SRV_IF/resolv.conf"
echo "nameserver 192.168.100.2" >> "/etc/net/ifaces/$HQ_SRV_IF/resolv.conf"
restart_network_safe
cat > /etc/resolv.conf <<EOFINNER
search $DOMAIN
nameserver 192.168.100.2
EOFINNER

safe_apt_install openssh-server sudo bind bind-utils tzdata
timedatectl set-timezone "$TZ"

id "$SSH_USER" >/dev/null 2>&1 || useradd -m -u 2026 -s /bin/bash "$SSH_USER"
echo "$SSH_USER:$DEMO_PASS" | chpasswd

mkdir -p /etc/sudoers.d /etc/ssh
echo "$SSH_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$SSH_USER"
chmod 440 "/etc/sudoers.d/$SSH_USER"
echo 'Authorized access only' > /etc/ssh/banner

SSHD_CONF="/etc/ssh/sshd_config"
[[ -f /etc/openssh/sshd_config ]] && SSHD_CONF="/etc/openssh/sshd_config"
sed -i '/^# BEGIN DEMO SSH$/,/^# END DEMO SSH$/d' "$SSHD_CONF"
cat >> "$SSHD_CONF" <<EOFINNER

# BEGIN DEMO SSH
Port 2026
AllowUsers $SSH_USER
MaxAuthTries 2
Banner /etc/ssh/banner
# END DEMO SSH
EOFINNER

systemctl enable --now sshd
systemctl restart sshd

systemctl disable --now bind 2>/dev/null || true

mkdir -p /var/lib/bind/etc/zones /var/lib/bind/run/named
cat > /var/lib/bind/etc/named-direct.conf <<'EOFINNER'
options {
    directory "/etc";
    pid-file "/run/named/named.pid";
    listen-on port 53 { any; };
    listen-on-v6 { none; };
    allow-query { any; };
    recursion yes;
    allow-recursion { any; };
    dnssec-validation no;
};

zone "au-team.irpo" {
    type master;
    file "/etc/zones/au-team.irpo.zone";
};

zone "100.168.192.in-addr.arpa" {
    type master;
    file "/etc/zones/100.168.192.zone";
};

zone "200.168.192.in-addr.arpa" {
    type master;
    file "/etc/zones/200.168.192.zone";
};

zone "10.168.192.in-addr.arpa" {
    type master;
    file "/etc/zones/10.168.192.zone";
};
EOFINNER

cat > /var/lib/bind/etc/zones/au-team.irpo.zone <<'EOFINNER'
$TTL 3600
@       IN SOA  hq-srv.au-team.irpo. admin.au-team.irpo. (
                2026060301 3600 900 604800 86400 )
        IN NS   hq-srv.au-team.irpo.

hq-srv  IN A    192.168.100.2
hq-rtr  IN A    192.168.100.1
hq-cli  IN A    192.168.200.11
br-rtr  IN A    192.168.10.1
br-srv  IN A    192.168.10.2
web     IN A    172.16.1.1
docker  IN A    172.16.2.1
EOFINNER

cat > /var/lib/bind/etc/zones/100.168.192.zone <<'EOFINNER'
$TTL 3600
@       IN SOA  hq-srv.au-team.irpo. admin.au-team.irpo. (
                2026060301 3600 900 604800 86400 )
        IN NS   hq-srv.au-team.irpo.

1       IN PTR  hq-rtr.au-team.irpo.
2       IN PTR  hq-srv.au-team.irpo.
EOFINNER

cat > /var/lib/bind/etc/zones/200.168.192.zone <<'EOFINNER'
$TTL 3600
@       IN SOA  hq-srv.au-team.irpo. admin.au-team.irpo. (
                2026060301 3600 900 604800 86400 )
        IN NS   hq-srv.au-team.irpo.

11      IN PTR  hq-cli.au-team.irpo.
EOFINNER

cat > /var/lib/bind/etc/zones/10.168.192.zone <<'EOFINNER'
$TTL 3600
@       IN SOA  hq-srv.au-team.irpo. admin.au-team.irpo. (
                2026060301 3600 900 604800 86400 )
        IN NS   hq-srv.au-team.irpo.

1       IN PTR  br-rtr.au-team.irpo.
2       IN PTR  br-srv.au-team.irpo.
EOFINNER

chown -R named:named /var/lib/bind 2>/dev/null || true

cat > /etc/systemd/system/named-direct.service <<'EOFINNER'
[Unit]
Description=Direct BIND DNS Server for demo exam
After=network.target

[Service]
Type=simple
ExecStart=/usr/sbin/named -g -u named -t /var/lib/bind -c /etc/named-direct.conf
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOFINNER

named-checkconf -t /var/lib/bind /etc/named-direct.conf 2>/dev/null || true
systemctl daemon-reload
systemctl enable named-direct.service
systemctl restart named-direct.service

hostname || true
ip -br a || true
ip route || true
id "$SSH_USER" || true
sudo -l -U "$SSH_USER" || true
ss -tulpen | grep 2026 || true
systemctl is-active named-direct || true
ss -tulpen | grep ':53' || true
dig +short @127.0.0.1 hq-srv.au-team.irpo || true
dig +short @127.0.0.1 web.au-team.irpo || true
dig +short @127.0.0.1 docker.au-team.irpo || true
