set -euo pipefail

if [[ -f /tmp/de-run/de-inventory.env ]]; then
  set -a
  # shellcheck disable=SC1091
  source /tmp/de-run/de-inventory.env
  set +a
fi
if [[ -f /tmp/de-run/scripts/lib/common.sh ]]; then
  # shellcheck disable=SC1091
  source /tmp/de-run/scripts/lib/common.sh
fi

configure_sshd_port22() {
  local user="$1"
  local pass="$2"

  safe_apt_install openssh-server sudo python3 curl wget
  id "$user" >/dev/null 2>&1 || useradd -m -s /bin/bash "$user"
  echo "$user:$pass" | chpasswd
  mkdir -p /etc/sudoers.d
  echo "$user ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$user"
  chmod 440 "/etc/sudoers.d/$user"

  sshd_conf=/etc/ssh/sshd_config
  [[ -f /etc/openssh/sshd_config ]] && sshd_conf=/etc/openssh/sshd_config
  grep -q '^Port 22$' "$sshd_conf" || echo 'Port 22' >> "$sshd_conf"
  systemctl enable --now sshd
  systemctl restart sshd
  ss -tulpen | grep ':22' || true
}

host="$(hostname | tr '[:upper:]' '[:lower:]')"

case "$host" in
  hq-cli*)
    configure_sshd_port22 "$SSH_USER" "$SSH_PASS"
    echo "[OK] HQ-CLI SSH/python prepared for Ansible"
    ;;

  hq-rtr*|br-rtr*)
    configure_sshd_port22 "$ROUTER_ADMIN_USER" "$ROUTER_ADMIN_PASS"
    echo "[OK] router SSH/python prepared for Ansible"
    ;;

  br-srv*)
    if safe_apt_install ansible sshpass; then
      echo "[OK] ansible and sshpass package install attempted"
    elif safe_apt_install ansible; then
      echo "[WARN] sshpass package unavailable; ansible installed"
    else
      echo "[FAIL] ansible package installation failed"
      echo "Command: apt-get install -y ansible sshpass"
      echo "Next hint: check ALT repositories and DNS from BR-SRV"
      exit 1
    fi

    command -v ansible >/dev/null 2>&1

    mkdir -p "$ANSIBLE_WORKDIR"
    cat > "$ANSIBLE_WORKDIR/ansible.cfg" <<EOFINNER
[defaults]
inventory = $ANSIBLE_WORKDIR/hosts
host_key_checking = False
retry_files_enabled = False
timeout = 15
interpreter_python = auto_silent
EOFINNER

    cat > "$ANSIBLE_WORKDIR/hosts" <<EOFINNER
[module2]
hq-srv ansible_host=$HQ_SRV_ADDR ansible_user=$SSH_USER ansible_port=$SSH_PORT ansible_password=$SSH_PASS
hq-cli ansible_host=$HQ_CLI_ADDR ansible_user=$SSH_USER ansible_port=22 ansible_password=$SSH_PASS
hq-rtr ansible_host=$HQ_RTR_WAN_ADDR ansible_user=$ROUTER_ADMIN_USER ansible_password=$ROUTER_ADMIN_PASS
br-rtr ansible_host=$BR_RTR_WAN_ADDR ansible_user=$ROUTER_ADMIN_USER ansible_password=$ROUTER_ADMIN_PASS

[all:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
EOFINNER

    echo "[OK] Ansible inventory written to $ANSIBLE_WORKDIR/hosts"
    ansible --version
    cd "$ANSIBLE_WORKDIR"
    ansible all -m ping
    echo "[OK] ansible all -m ping"
    ;;

  *)
    echo "[FAIL] Unsupported Ansible target host: $host"
    echo "Command: hostname"
    echo "Next hint: run module2-ansible only on BR-SRV/HQ-CLI/HQ-RTR/BR-RTR"
    exit 1
    ;;
esac
