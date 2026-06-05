hostnamectl set-hostname HQ-SRV

reverse_zone_from_net() {
  local cidr="$1"
  local ip="${cidr%/*}"
  local a b c d
  IFS=. read -r a b c d <<EOFINNER
$ip
EOFINNER
  printf '%s.%s.%s.in-addr.arpa\n' "$c" "$b" "$a"
}

last_octet() {
  local ip="${1%/*}"
  printf '%s\n' "${ip##*.}"
}

write_eth_static "$HQ_SRV_IF" "$HQ_SRV_IP" "$HQ_SRV_GW"
cat > "/etc/net/ifaces/$HQ_SRV_IF/resolv.conf" <<EOFINNER
nameserver $DNS_FORWARDER_1
nameserver $DNS_FORWARDER_2
nameserver 8.8.8.8
EOFINNER
restart_network_safe
cat > /etc/resolv.conf <<EOFINNER
nameserver $DNS_FORWARDER_1
nameserver $DNS_FORWARDER_2
nameserver 8.8.8.8
EOFINNER

apt-get update
apt-get install -y bind bind-utils sudo openssh-server tzdata
timedatectl set-timezone "$TZ"

id "$SSH_USER" >/dev/null 2>&1 || useradd -m -u "$SSH_UID" -s /bin/bash "$SSH_USER"
echo "$SSH_USER:$SSH_PASS" | chpasswd

mkdir -p /etc/sudoers.d /etc/ssh
echo "$SSH_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$SSH_USER"
chmod 440 "/etc/sudoers.d/$SSH_USER"
echo 'Authorized access only' > /etc/ssh/banner

SSHD_CONF="/etc/ssh/sshd_config"
[[ -f /etc/openssh/sshd_config ]] && SSHD_CONF="/etc/openssh/sshd_config"
sed -i '/^# BEGIN DEMO SSH$/,/^# END DEMO SSH$/d' "$SSHD_CONF"
cat >> "$SSHD_CONF" <<EOFINNER

# BEGIN DEMO SSH
Port $SSH_PORT
AllowUsers $SSH_USER
MaxAuthTries 2
Banner /etc/ssh/banner
# END DEMO SSH
EOFINNER

systemctl enable --now sshd
systemctl restart sshd

systemctl disable --now bind 2>/dev/null || true

HQ_SRV_REV_ZONE="$(reverse_zone_from_net "$HQ_SRV_NET")"
HQ_CLI_REV_ZONE="$(reverse_zone_from_net "$HQ_CLI_NET")"
BR_SRV_REV_ZONE="$(reverse_zone_from_net "$BR_SRV_NET")"

mkdir -p /var/lib/bind/etc/zones /var/lib/bind/run/named
cat > /var/lib/bind/etc/named-direct.conf <<EOFINNER
options {
    directory "/etc";
    pid-file "/run/named/named.pid";
    listen-on port 53 { any; };
    listen-on-v6 { none; };
    allow-query { any; };
    recursion yes;
    allow-recursion { any; };
    forwarders { $DNS_FORWARDER_1; $DNS_FORWARDER_2; };
    dnssec-validation no;
};

zone "$DOMAIN" {
    type master;
    file "/etc/zones/$DOMAIN.zone";
};

zone "$HQ_SRV_REV_ZONE" {
    type master;
    file "/etc/zones/$HQ_SRV_REV_ZONE.zone";
};

zone "$HQ_CLI_REV_ZONE" {
    type master;
    file "/etc/zones/$HQ_CLI_REV_ZONE.zone";
};

zone "$BR_SRV_REV_ZONE" {
    type master;
    file "/etc/zones/$BR_SRV_REV_ZONE.zone";
};
EOFINNER

cat > "/var/lib/bind/etc/zones/$DOMAIN.zone" <<EOFINNER
\$TTL 3600
@       IN SOA  hq-srv.$DOMAIN. admin.$DOMAIN. (
                2026060501 3600 900 604800 86400 )
        IN NS   hq-srv.$DOMAIN.

hq-srv  IN A    $HQ_SRV_ADDR
hq-rtr  IN A    $HQ_RTR_SRV_ADDR
hq-cli  IN A    $HQ_CLI_EXPECTED_IP
br-rtr  IN A    $BR_RTR_LAN_ADDR
br-srv  IN A    $BR_SRV_ADDR
web     IN A    $DNS_WEB_IP
docker  IN A    $DNS_DOCKER_IP
EOFINNER

cat > "/var/lib/bind/etc/zones/$HQ_SRV_REV_ZONE.zone" <<EOFINNER
\$TTL 3600
@       IN SOA  hq-srv.$DOMAIN. admin.$DOMAIN. (
                2026060501 3600 900 604800 86400 )
        IN NS   hq-srv.$DOMAIN.

$(last_octet "$HQ_RTR_SRV_ADDR")       IN PTR  hq-rtr.$DOMAIN.
$(last_octet "$HQ_SRV_ADDR")       IN PTR  hq-srv.$DOMAIN.
EOFINNER

cat > "/var/lib/bind/etc/zones/$HQ_CLI_REV_ZONE.zone" <<EOFINNER
\$TTL 3600
@       IN SOA  hq-srv.$DOMAIN. admin.$DOMAIN. (
                2026060501 3600 900 604800 86400 )
        IN NS   hq-srv.$DOMAIN.

$(last_octet "$HQ_CLI_EXPECTED_IP")      IN PTR  hq-cli.$DOMAIN.
EOFINNER

cat > "/var/lib/bind/etc/zones/$BR_SRV_REV_ZONE.zone" <<EOFINNER
\$TTL 3600
@       IN SOA  hq-srv.$DOMAIN. admin.$DOMAIN. (
                2026060501 3600 900 604800 86400 )
        IN NS   hq-srv.$DOMAIN.

$(last_octet "$BR_RTR_LAN_ADDR")       IN PTR  br-rtr.$DOMAIN.
$(last_octet "$BR_SRV_ADDR")       IN PTR  br-srv.$DOMAIN.
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

cat > "/etc/net/ifaces/$HQ_SRV_IF/resolv.conf" <<EOFINNER
search $DOMAIN
nameserver $HQ_SRV_ADDR
EOFINNER
cat > /etc/resolv.conf <<EOFINNER
search $DOMAIN
nameserver $HQ_SRV_ADDR
EOFINNER

hostname || true
ip -br a || true
ip route || true
id "$SSH_USER" || true
sudo -l -U "$SSH_USER" || true
ss -tulpen | grep "$SSH_PORT" || true
systemctl is-active named-direct || true
ss -tulpen | grep ':53' || true
dig +short @127.0.0.1 "hq-srv.$DOMAIN" || true
dig +short @127.0.0.1 "web.$DOMAIN" || true
dig +short @127.0.0.1 "docker.$DOMAIN" || true
