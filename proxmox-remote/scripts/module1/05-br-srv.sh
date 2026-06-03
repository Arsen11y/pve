hostnamectl set-hostname BR-SRV

write_eth_static "$BR_SRV_IF" "$BR_SRV_IP" "$BR_SRV_GW"
echo "search $DOMAIN" > "/etc/net/ifaces/$BR_SRV_IF/resolv.conf"
echo "nameserver 192.168.100.2" >> "/etc/net/ifaces/$BR_SRV_IF/resolv.conf"
restart_network_safe
cat > /etc/resolv.conf <<EOFINNER
search $DOMAIN
nameserver 192.168.100.2
EOFINNER

safe_apt_install openssh-server sudo tzdata
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

ip -br a || true
ip route || true
id "$SSH_USER" || true
sudo -l -U "$SSH_USER" || true
ss -tulpen | grep 2026 || true
ping -c 4 192.168.100.2 || true
ping -c 4 8.8.8.8 || true
