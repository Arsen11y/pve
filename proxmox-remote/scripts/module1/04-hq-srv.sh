hostnamectl set-hostname HQ-SRV

write_eth_static "$HQ_SRV_IF" "$HQ_SRV_IP" "$HQ_SRV_GW"
restart_network_safe

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

grep -q '^Port 2026' "$SSHD_CONF" || cat >> "$SSHD_CONF" <<EOFINNER

Port 2026
AllowUsers $SSH_USER
MaxAuthTries 2
Banner /etc/ssh/banner
EOFINNER

systemctl enable --now sshd
systemctl restart sshd

basic_check
id "$SSH_USER"
sudo -l -U "$SSH_USER" || true
ss -tulpen | grep 2026 || true
