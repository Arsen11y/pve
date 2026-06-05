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

host="$(hostname | tr '[:upper:]' '[:lower:]')"
if [[ "$host" != br-srv* ]]; then
  echo "[FAIL] Unsupported Ansible target host: $host"
  echo "Command: hostname"
  echo "Next hint: run module2-ansible only on BR-SRV"
  exit 1
fi

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

if ! command -v ansible >/dev/null 2>&1; then
  echo "[FAIL] ansible command is unavailable"
  echo "Command: command -v ansible"
  echo "Next hint: check ansible package name on ALT"
  exit 1
fi

mkdir -p "$ANSIBLE_WORKDIR"
cat > "$ANSIBLE_WORKDIR/ansible.cfg" <<EOFINNER
[defaults]
inventory = $ANSIBLE_WORKDIR/hosts
host_key_checking = False
retry_files_enabled = False
timeout = 10
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

if timeout 5 bash -c "</dev/tcp/$HQ_CLI_ADDR/22" 2>/dev/null; then
  echo "[OK] hq-cli ssh appears reachable on port 22"
else
  echo "[WARN] hq-cli ssh unavailable on port 22"
  echo "Next hint: HQ-CLI SSH is not part of Module 1; configure it before expecting ansible ping for hq-cli"
fi

cd "$ANSIBLE_WORKDIR"
if ansible all -m ping; then
  echo "[OK] ansible all -m ping"
else
  echo "[FAIL] ansible ping failed"
  echo "Command: cd $ANSIBLE_WORKDIR && ansible all -m ping"
  echo "Next hint: check SSH users/ports and install sshpass if password auth is required"
fi
