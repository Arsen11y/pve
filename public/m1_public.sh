#!/usr/bin/env bash
set -euo pipefail

ROOT="/tmp/module1-remote"
LOG="/root/module1-demo-run.log"
MODE="${1:-run}"

ISP_VMID=10101
HQ_RTR_VMID=10102
HQ_SRV_VMID=10103
HQ_CLI_VMID=10104
BR_RTR_VMID=10105
BR_SRV_VMID=10106

TZ="Europe/Kaliningrad"
DOMAIN="au-team.irpo"

SSH_USER="sshuser"
SSH_UID=2013
SSH_PASS="P@ssw0rd"
SSH_PORT=2013
ADMIN_USER="net_admin"
ADMIN_PASS="P@ssw0rd"

VLAN_SRV=113
VLAN_CLI=213
VLAN_MGMT=813

ISP_WAN_IF="enp7s1"
ISP_HQ_IF="enp7s2"
ISP_BR_IF="enp7s3"
HQ_RTR_WAN_IF="enp7s1"
HQ_RTR_LAN_IF="enp7s2"
BR_RTR_WAN_IF="enp7s1"
BR_RTR_LAN_IF="enp7s2"
HQ_SRV_IF="enp7s1"
HQ_CLI_IF="enp7s1"
BR_SRV_IF="enp7s1"

ISP_HQ_NET="172.16.50.0/28"
ISP_HQ_IP="172.16.50.1/28"
ISP_HQ_ADDR="172.16.50.1"
HQ_RTR_WAN_IP="172.16.50.2/28"
HQ_RTR_WAN_ADDR="172.16.50.2"
HQ_RTR_WAN_GW="172.16.50.1"

ISP_BR_NET="172.16.60.0/28"
ISP_BR_IP="172.16.60.1/28"
ISP_BR_ADDR="172.16.60.1"
BR_RTR_WAN_IP="172.16.60.2/28"
BR_RTR_WAN_ADDR="172.16.60.2"
BR_RTR_WAN_GW="172.16.60.1"

HQ_SRV_NET="192.168.113.0/27"
HQ_RTR_SRV_ADDR="192.168.113.1"
HQ_SRV_IP="192.168.113.2/27"
HQ_SRV_ADDR="192.168.113.2"

HQ_CLI_NET="192.168.213.0/27"
HQ_RTR_CLI_ADDR="192.168.213.1"
HQ_CLI_DHCP_START="192.168.213.10"
HQ_CLI_DHCP_END="192.168.213.20"
HQ_CLI_ADDR="192.168.213.11"

MGMT_NET="192.168.81.0/29"
HQ_RTR_MGMT_ADDR="192.168.81.1"

BR_SRV_NET="192.168.10.0/28"
BR_RTR_LAN_IP="192.168.10.1/28"
BR_RTR_LAN_ADDR="192.168.10.1"
BR_SRV_IP="192.168.10.2/28"
BR_SRV_ADDR="192.168.10.2"

GRE_NAME="gre1"
GRE_HQ_IP="10.10.10.1/30"
GRE_HQ_ADDR="10.10.10.1"
GRE_BR_IP="10.10.10.2/30"
GRE_BR_ADDR="10.10.10.2"

DNS_FORWARDER_1="77.88.8.7"
DNS_FORWARDER_2="77.88.8.3"
DNS_FORWARDER_FALLBACK="8.8.8.8"
DNS_HTTP_IP="$ISP_HQ_ADDR"
DNS_APP_IP="$ISP_BR_ADDR"
HTTP_ALIAS="$(printf 'we%s' b)"
APP_ALIAS="$(printf 'do%s' cker)"

HQ_SRV_PVE_NET="net6"
HQ_CLI_PVE_NET="net6"

usage() {
  cat <<'EOF'
Usage:
  ./m1_public.sh
  ./m1_public.sh run
  ./m1_public.sh check
EOF
}

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root on Proxmox."
    exit 1
  fi
}

target_vmid() {
  case "$1" in
    isp) echo "$ISP_VMID" ;;
    hq-rtr) echo "$HQ_RTR_VMID" ;;
    br-rtr) echo "$BR_RTR_VMID" ;;
    hq-srv) echo "$HQ_SRV_VMID" ;;
    br-srv) echo "$BR_SRV_VMID" ;;
    hq-cli) echo "$HQ_CLI_VMID" ;;
    *) return 1 ;;
  esac
}

guest_ping() {
  qm agent "$1" ping >/dev/null 2>&1
}

wait_agent() {
  local vmid="$1"
  local waited=0
  while (( waited < 180 )); do
    guest_ping "$vmid" && return 0
    sleep 5
    waited=$((waited + 5))
  done
  return 1
}

parse_guest_result() {
  local raw="$1"
  local qerr="$2"
  local out="$3"
  local err="$4"
  local meta="$5"
  local rc="$6"
  python3 - "$raw" "$qerr" "$out" "$err" "$meta" "$rc" <<'PY'
import json, re, sys
raw_path, qerr_path, out_path, err_path, meta_path, rc = sys.argv[1:]
raw = open(raw_path, encoding="utf-8", errors="replace").read()
qerr = open(qerr_path, encoding="utf-8", errors="replace").read()
combined = raw + "\n" + qerr
try:
    data = json.loads(raw) if raw.strip() else {}
except Exception:
    data = {}

def num(name):
    if name in data and data[name] not in (None, ""):
        try:
            return int(data[name])
        except Exception:
            pass
    m = re.search(rf'(?mi)^\s*{re.escape(name)}\s*[:=]\s*(-?\d+|true|false)\s*$', combined)
    if not m:
        return None
    v = m.group(1).lower()
    if v == "true":
        return 1
    if v == "false":
        return 0
    return int(v)

pid = num("pid")
if pid is None:
    m = re.search(r'(?i)\bpid\b[^0-9]*(\d+)', combined)
    if m:
        pid = int(m.group(1))
exitcode = num("exitcode")
exited = num("exited")
out_data = data.get("out-data", data.get("out_data", "")) or ""
err_data = data.get("err-data", data.get("err_data", "")) or ""
timeout = re.search(r'(?i)timeout reached.*returning pid', combined)
if qerr and not timeout:
    err_data = (err_data + "\n" if err_data else "") + qerr
if exitcode is None:
    if pid is not None:
        exitcode, state = 124, "running"
    elif exited == 1:
        exitcode, state = 0, "exited"
    else:
        exitcode, state = int(rc), "failed" if int(rc) else "unknown"
else:
    state = "exited"
open(out_path, "w", encoding="utf-8").write(str(out_data))
open(err_path, "w", encoding="utf-8").write(str(err_data))
open(meta_path, "w", encoding="utf-8").write(f"exitcode={exitcode}\npid={pid or ''}\nstate={state}\n")
PY
}

meta_value() {
  awk -F= -v key="$2" '$1 == key {print substr($0, length(key) + 2)}' "$1" | tail -n1
}

guest_exec_capture() {
  local vmid="$1"
  local cmd="$2"
  local out="$3"
  local err="$4"
  local meta="$5"
  local raw qerr rc state pid waited status_raw status_err
  raw="$(mktemp)"
  qerr="$(mktemp)"
  if qm guest exec "$vmid" -- bash -lc "$cmd" >"$raw" 2>"$qerr"; then
    rc=0
  else
    rc=$?
  fi
  parse_guest_result "$raw" "$qerr" "$out" "$err" "$meta" "$rc"
  rm -f "$raw" "$qerr"

  state="$(meta_value "$meta" state)"
  pid="$(meta_value "$meta" pid)"
  waited=0
  while [[ "$state" == "running" && -n "$pid" && "$waited" -lt 900 ]]; do
    sleep 5
    waited=$((waited + 5))
    status_raw="$(mktemp)"
    status_err="$(mktemp)"
    if qm guest exec-status "$vmid" "$pid" >"$status_raw" 2>"$status_err"; then
      rc=0
    else
      rc=$?
    fi
    parse_guest_result "$status_raw" "$status_err" "$out" "$err" "$meta" "$rc"
    rm -f "$status_raw" "$status_err"
    state="$(meta_value "$meta" state)"
  done

  if [[ "$state" == "running" ]]; then
    {
      cat "$err" 2>/dev/null || true
      echo "Timeout waiting for guest pid $pid."
      echo "Next hint: qm guest exec-status $vmid $pid"
    } >"${err}.tmp"
    mv "${err}.tmp" "$err"
    printf 'exitcode=124\npid=%s\nstate=wait_timeout\n' "$pid" >"$meta"
  fi
}

print_block() {
  local title="$1"
  local file="$2"
  [[ -s "$file" ]] || return 0
  echo
  echo "[$title]"
  cat "$file"
}

guest_exec_pretty() {
  local target="$1"
  local vmid="$2"
  local label="$3"
  local cmd="$4"
  local tmp out err meta exitcode pid state
  tmp="$(mktemp -d)"
  out="$tmp/out"
  err="$tmp/err"
  meta="$tmp/meta"
  echo
  echo "============================================================"
  echo "[RUN] target=$target vmid=$vmid action=$label"
  echo "============================================================"
  if ! guest_ping "$vmid"; then
    echo "[FAIL] qemu-guest-agent unavailable"
    rm -rf "$tmp"
    return 1
  fi
  echo "[OK] qemu-guest-agent available"
  guest_exec_capture "$vmid" "$cmd" "$out" "$err" "$meta"
  print_block STDOUT "$out"
  print_block STDERR "$err"
  exitcode="$(meta_value "$meta" exitcode)"
  pid="$(meta_value "$meta" pid)"
  state="$(meta_value "$meta" state)"
  echo
  echo "[RESULT]"
  [[ -n "$pid" ]] && echo "guest_pid=$pid"
  echo "guest_exitcode=$exitcode"
  echo "state=$state"
  if [[ "$exitcode" == "0" ]]; then
    echo "status=OK"
    rm -rf "$tmp"
    return 0
  fi
  echo "status=FAIL"
  rm -rf "$tmp"
  return 1
}

base64_file() {
  if base64 --help 2>&1 | grep -q -- '-w'; then
    base64 -w0 "$1"
  else
    base64 "$1" | tr -d '\n'
  fi
}

guest_put() {
  local target="$1"
  local vmid="$2"
  local src="$3"
  local dest="$4"
  local mode="${5:-0644}"
  local b64 cmd
  b64="$(base64_file "$src")"
  cmd="$(cat <<EOF
set -e
mkdir -p "$(dirname "$dest")"
base64 -d > "$dest" <<'EOF_B64'
$b64
EOF_B64
chmod "$mode" "$dest"
EOF
)"
  guest_exec_pretty "$target" "$vmid" "transfer" "$cmd" >/dev/null
}

write_common() {
  cat > "$ROOT/common.sh" <<'EOF'
ensure_iface_dir() {
  mkdir -p "/etc/net/ifaces/$1"
}

write_eth_static() {
  local ifname="$1"
  local ipaddr="$2"
  local gw="${3:-}"
  ensure_iface_dir "$ifname"
  cat > "/etc/net/ifaces/$ifname/options" <<EOFINNER
TYPE=eth
EOFINNER
  echo "$ipaddr" > "/etc/net/ifaces/$ifname/ipv4address"
  if [[ -n "$gw" ]]; then
    echo "default via $gw" > "/etc/net/ifaces/$ifname/ipv4route"
  fi
}

write_eth_dhcp() {
  local ifname="$1"
  ensure_iface_dir "$ifname"
  cat > "/etc/net/ifaces/$ifname/options" <<EOFINNER
TYPE=eth
BOOTPROTO=dhcp
EOFINNER
}

enable_ip_forward() {
  mkdir -p /etc/net
  grep -q '^net.ipv4.ip_forward' /etc/net/sysctl.conf 2>/dev/null \
    && sed -i 's/^net.ipv4.ip_forward.*/net.ipv4.ip_forward = 1/' /etc/net/sysctl.conf \
    || echo 'net.ipv4.ip_forward = 1' >> /etc/net/sysctl.conf
  sysctl -w net.ipv4.ip_forward=1
}

safe_apt_install() {
  apt-get update || true
  apt-get install -y "$@"
}

restart_network_safe() {
  systemctl restart network
}
EOF
}

write_env() {
  cat > "$ROOT/env.sh" <<EOF
export TZ='$TZ'
export DOMAIN='$DOMAIN'
export SSH_USER='$SSH_USER'
export SSH_UID='$SSH_UID'
export SSH_PASS='$SSH_PASS'
export SSH_PORT='$SSH_PORT'
export ADMIN_USER='$ADMIN_USER'
export ADMIN_PASS='$ADMIN_PASS'
export VLAN_SRV='$VLAN_SRV'
export VLAN_CLI='$VLAN_CLI'
export VLAN_MGMT='$VLAN_MGMT'
export ISP_WAN_IF='$ISP_WAN_IF'
export ISP_HQ_IF='$ISP_HQ_IF'
export ISP_BR_IF='$ISP_BR_IF'
export HQ_RTR_WAN_IF='$HQ_RTR_WAN_IF'
export HQ_RTR_LAN_IF='$HQ_RTR_LAN_IF'
export BR_RTR_WAN_IF='$BR_RTR_WAN_IF'
export BR_RTR_LAN_IF='$BR_RTR_LAN_IF'
export HQ_SRV_IF='$HQ_SRV_IF'
export HQ_CLI_IF='$HQ_CLI_IF'
export BR_SRV_IF='$BR_SRV_IF'
export ISP_HQ_NET='$ISP_HQ_NET'
export ISP_HQ_IP='$ISP_HQ_IP'
export ISP_HQ_ADDR='$ISP_HQ_ADDR'
export HQ_RTR_WAN_IP='$HQ_RTR_WAN_IP'
export HQ_RTR_WAN_ADDR='$HQ_RTR_WAN_ADDR'
export HQ_RTR_WAN_GW='$HQ_RTR_WAN_GW'
export ISP_BR_NET='$ISP_BR_NET'
export ISP_BR_IP='$ISP_BR_IP'
export ISP_BR_ADDR='$ISP_BR_ADDR'
export BR_RTR_WAN_IP='$BR_RTR_WAN_IP'
export BR_RTR_WAN_ADDR='$BR_RTR_WAN_ADDR'
export BR_RTR_WAN_GW='$BR_RTR_WAN_GW'
export HQ_SRV_NET='$HQ_SRV_NET'
export HQ_RTR_SRV_ADDR='$HQ_RTR_SRV_ADDR'
export HQ_SRV_IP='$HQ_SRV_IP'
export HQ_SRV_ADDR='$HQ_SRV_ADDR'
export HQ_CLI_NET='$HQ_CLI_NET'
export HQ_RTR_CLI_ADDR='$HQ_RTR_CLI_ADDR'
export HQ_CLI_DHCP_START='$HQ_CLI_DHCP_START'
export HQ_CLI_DHCP_END='$HQ_CLI_DHCP_END'
export HQ_CLI_ADDR='$HQ_CLI_ADDR'
export MGMT_NET='$MGMT_NET'
export HQ_RTR_MGMT_ADDR='$HQ_RTR_MGMT_ADDR'
export BR_SRV_NET='$BR_SRV_NET'
export BR_RTR_LAN_IP='$BR_RTR_LAN_IP'
export BR_RTR_LAN_ADDR='$BR_RTR_LAN_ADDR'
export BR_SRV_IP='$BR_SRV_IP'
export BR_SRV_ADDR='$BR_SRV_ADDR'
export GRE_NAME='$GRE_NAME'
export GRE_HQ_IP='$GRE_HQ_IP'
export GRE_HQ_ADDR='$GRE_HQ_ADDR'
export GRE_BR_IP='$GRE_BR_IP'
export GRE_BR_ADDR='$GRE_BR_ADDR'
export DNS_FORWARDER_1='$DNS_FORWARDER_1'
export DNS_FORWARDER_2='$DNS_FORWARDER_2'
export DNS_FORWARDER_FALLBACK='$DNS_FORWARDER_FALLBACK'
export DNS_HTTP_IP='$DNS_HTTP_IP'
export DNS_APP_IP='$DNS_APP_IP'
export HTTP_ALIAS='$HTTP_ALIAS'
export APP_ALIAS='$APP_ALIAS'
EOF
}

write_guest_scripts() {
  mkdir -p "$ROOT/scripts"
  write_common
  write_env

  cat > "$ROOT/scripts/isp.sh" <<'EOF'
hostnamectl set-hostname ISP
write_eth_dhcp "$ISP_WAN_IF"
write_eth_static "$ISP_HQ_IF" "$ISP_HQ_IP"
write_eth_static "$ISP_BR_IF" "$ISP_BR_IP"
safe_apt_install nftables tzdata
timedatectl set-timezone "$TZ"
enable_ip_forward
mkdir -p /etc/nftables
cat > /etc/nftables/nftables.nft <<EOFINNER
#!/usr/sbin/nft -f
flush ruleset
table ip nat {
    chain postrouting {
        type nat hook postrouting priority srcnat;
        oifname "$ISP_WAN_IF" masquerade
    }
}
EOFINNER
systemctl enable nftables
restart_network_safe
systemctl restart nftables
hostname
ip -br a
ip route
cat /proc/sys/net/ipv4/ip_forward
nft list ruleset
ping -c 4 8.8.8.8 || true
EOF

  cat > "$ROOT/scripts/hq-rtr.sh" <<'EOF'
hostnamectl set-hostname HQ-RTR
write_eth_static "$HQ_RTR_WAN_IF" "$HQ_RTR_WAN_IP" "$HQ_RTR_WAN_GW"
cat > "/etc/net/ifaces/$HQ_RTR_WAN_IF/resolv.conf" <<EOFINNER
nameserver $DNS_FORWARDER_1
nameserver $DNS_FORWARDER_2
nameserver $DNS_FORWARDER_FALLBACK
EOFINNER
cat > /etc/resolv.conf <<EOFINNER
nameserver $DNS_FORWARDER_1
nameserver $DNS_FORWARDER_2
nameserver $DNS_FORWARDER_FALLBACK
EOFINNER
restart_network_safe
ip -br a || true
ip route || true
ping -c 4 "$HQ_RTR_WAN_GW" || true
safe_apt_install nftables sudo dhcp-server frr tzdata
timedatectl set-timezone "$TZ"
id "$ADMIN_USER" >/dev/null 2>&1 || useradd -m -s /bin/bash "$ADMIN_USER"
echo "$ADMIN_USER:$ADMIN_PASS" | chpasswd
mkdir -p /etc/sudoers.d
echo "$ADMIN_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$ADMIN_USER"
chmod 440 "/etc/sudoers.d/$ADMIN_USER"
ensure_iface_dir "$HQ_RTR_LAN_IF"
cat > "/etc/net/ifaces/$HQ_RTR_LAN_IF/options" <<EOFINNER
TYPE=eth
EOFINNER
rm -f "/etc/net/ifaces/$HQ_RTR_LAN_IF/ipv4address" "/etc/net/ifaces/$HQ_RTR_LAN_IF/ipv4route"
for vid in "$VLAN_SRV" "$VLAN_CLI" "$VLAN_MGMT"; do
  ensure_iface_dir "$HQ_RTR_LAN_IF.$vid"
done
for item in "$VLAN_SRV:$HQ_RTR_SRV_ADDR/27" "$VLAN_CLI:$HQ_RTR_CLI_ADDR/27" "$VLAN_MGMT:$HQ_RTR_MGMT_ADDR/29"; do
  vid="${item%%:*}"
  addr="${item#*:}"
  cat > "/etc/net/ifaces/$HQ_RTR_LAN_IF.$vid/options" <<EOFINNER
TYPE=vlan
HOST=$HQ_RTR_LAN_IF
VID=$vid
BOOTPROTO=static
EOFINNER
  echo "$addr" > "/etc/net/ifaces/$HQ_RTR_LAN_IF.$vid/ipv4address"
done
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
interface $GRE_NAME
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
cat > /etc/systemd/system/gre1-demo.service <<EOFINNER
[Unit]
Description=GRE tunnel for module 1
After=network.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=/bin/sh -c 'ip link set $GRE_NAME down 2>/dev/null || true'
ExecStartPre=/bin/sh -c 'ip tunnel del $GRE_NAME 2>/dev/null || true'
ExecStart=/bin/sh -c 'ip tunnel add $GRE_NAME mode gre local $HQ_RTR_WAN_ADDR remote $BR_RTR_WAN_ADDR ttl 255'
ExecStart=/bin/sh -c 'ip addr add $GRE_HQ_IP dev $GRE_NAME'
ExecStart=/bin/sh -c 'ip link set $GRE_NAME up multicast on'
ExecStart=/bin/sh -c 'ip route replace 10.10.10.0/30 dev $GRE_NAME'
ExecStart=/bin/sh -c 'ip route replace 224.0.0.0/4 dev $GRE_NAME'
ExecStop=/bin/sh -c 'ip link set $GRE_NAME down 2>/dev/null || true; ip tunnel del $GRE_NAME 2>/dev/null || true'
[Install]
WantedBy=multi-user.target
EOFINNER
systemctl enable nftables
restart_network_safe
systemctl restart nftables
for svc in dhcpd dhcp-server; do
  if systemctl cat "$svc" >/dev/null 2>&1; then
    systemctl enable "$svc"
    systemctl restart "$svc"
    break
  fi
done
systemctl daemon-reload
systemctl enable gre1-demo.service
systemctl restart gre1-demo.service
systemctl enable frr
systemctl restart frr
ip -br a
ip tunnel show "$GRE_NAME"
ping -c 4 "$GRE_BR_ADDR" || true
vtysh -c 'show ip ospf neighbor' || true
vtysh -c 'show ip route ospf' || true
EOF

  cat > "$ROOT/scripts/br-rtr.sh" <<'EOF'
hostnamectl set-hostname BR-RTR
write_eth_static "$BR_RTR_WAN_IF" "$BR_RTR_WAN_IP" "$BR_RTR_WAN_GW"
write_eth_static "$BR_RTR_LAN_IF" "$BR_RTR_LAN_IP"
cat > "/etc/net/ifaces/$BR_RTR_WAN_IF/resolv.conf" <<EOFINNER
nameserver $DNS_FORWARDER_1
nameserver $DNS_FORWARDER_2
nameserver $DNS_FORWARDER_FALLBACK
EOFINNER
cat > /etc/resolv.conf <<EOFINNER
nameserver $DNS_FORWARDER_1
nameserver $DNS_FORWARDER_2
nameserver $DNS_FORWARDER_FALLBACK
EOFINNER
restart_network_safe
ip -br a || true
ip route || true
ping -c 4 "$BR_RTR_WAN_GW" || true
safe_apt_install nftables sudo frr tzdata
timedatectl set-timezone "$TZ"
id "$ADMIN_USER" >/dev/null 2>&1 || useradd -m -s /bin/bash "$ADMIN_USER"
echo "$ADMIN_USER:$ADMIN_PASS" | chpasswd
mkdir -p /etc/sudoers.d
echo "$ADMIN_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$ADMIN_USER"
chmod 440 "/etc/sudoers.d/$ADMIN_USER"
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
interface $GRE_NAME
 ip ospf network point-to-point
 ip ospf mtu-ignore
router ospf
 ospf router-id 2.2.2.2
 network 10.10.10.0/30 area 0
 network $BR_SRV_NET area 0
EOFINNER
chown frr:frr /etc/frr/frr.conf /etc/frr/daemons 2>/dev/null || true
cat > /etc/systemd/system/gre1-demo.service <<EOFINNER
[Unit]
Description=GRE tunnel for module 1
After=network.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=/bin/sh -c 'ip link set $GRE_NAME down 2>/dev/null || true'
ExecStartPre=/bin/sh -c 'ip tunnel del $GRE_NAME 2>/dev/null || true'
ExecStart=/bin/sh -c 'ip tunnel add $GRE_NAME mode gre local $BR_RTR_WAN_ADDR remote $HQ_RTR_WAN_ADDR ttl 255'
ExecStart=/bin/sh -c 'ip addr add $GRE_BR_IP dev $GRE_NAME'
ExecStart=/bin/sh -c 'ip link set $GRE_NAME up multicast on'
ExecStart=/bin/sh -c 'ip route replace 10.10.10.0/30 dev $GRE_NAME'
ExecStart=/bin/sh -c 'ip route replace 224.0.0.0/4 dev $GRE_NAME'
ExecStop=/bin/sh -c 'ip link set $GRE_NAME down 2>/dev/null || true; ip tunnel del $GRE_NAME 2>/dev/null || true'
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
ip -br a
ip tunnel show "$GRE_NAME"
ping -c 4 "$GRE_HQ_ADDR" || true
vtysh -c 'show ip ospf neighbor' || true
vtysh -c 'show ip route ospf' || true
EOF

  cat > "$ROOT/scripts/hq-srv.sh" <<'EOF'
hostnamectl set-hostname HQ-SRV
write_eth_static "$HQ_SRV_IF" "$HQ_SRV_IP" "$HQ_RTR_SRV_ADDR"
cat > "/etc/net/ifaces/$HQ_SRV_IF/resolv.conf" <<EOFINNER
nameserver $DNS_FORWARDER_1
nameserver $DNS_FORWARDER_2
nameserver $DNS_FORWARDER_FALLBACK
EOFINNER
restart_network_safe
ip route replace default via "$HQ_RTR_SRV_ADDR" dev "$HQ_SRV_IF" || true
cat > /etc/resolv.conf <<EOFINNER
nameserver $DNS_FORWARDER_1
nameserver $DNS_FORWARDER_2
nameserver $DNS_FORWARDER_FALLBACK
EOFINNER
grep -q '^62\.152\.55\.238[[:space:]]ftp\.altlinux\.org$' /etc/hosts || echo '62.152.55.238 ftp.altlinux.org' >> /etc/hosts
ip -br a || true
ip route || true
cat /etc/resolv.conf || true
getent hosts ftp.altlinux.org || true
ping -c 4 "$HQ_RTR_SRV_ADDR" || true
ping -c 4 "$DNS_FORWARDER_FALLBACK" || true
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
sed -i '/^# BEGIN M1 SSH$/,/^# END M1 SSH$/d' "$SSHD_CONF"
cat >> "$SSHD_CONF" <<EOFINNER
# BEGIN M1 SSH
Port $SSH_PORT
AllowUsers $SSH_USER
MaxAuthTries 2
Banner /etc/ssh/banner
# END M1 SSH
EOFINNER
systemctl enable --now sshd
systemctl restart sshd
systemctl disable --now bind 2>/dev/null || true
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
    forwarders { $DNS_FORWARDER_1; $DNS_FORWARDER_2; $DNS_FORWARDER_FALLBACK; };
    dnssec-validation no;
};
zone "$DOMAIN" { type master; file "/etc/zones/$DOMAIN.zone"; };
zone "113.168.192.in-addr.arpa" { type master; file "/etc/zones/113.168.192.in-addr.arpa.zone"; };
zone "213.168.192.in-addr.arpa" { type master; file "/etc/zones/213.168.192.in-addr.arpa.zone"; };
zone "10.168.192.in-addr.arpa" { type master; file "/etc/zones/10.168.192.in-addr.arpa.zone"; };
EOFINNER
cat > "/var/lib/bind/etc/zones/$DOMAIN.zone" <<EOFINNER
\$TTL 3600
@       IN SOA  hq-srv.$DOMAIN. admin.$DOMAIN. (2025010101 3600 900 604800 86400)
        IN NS   hq-srv.$DOMAIN.
hq-srv  IN A    $HQ_SRV_ADDR
hq-rtr  IN A    $HQ_RTR_SRV_ADDR
hq-cli  IN A    $HQ_CLI_ADDR
br-rtr  IN A    $BR_RTR_LAN_ADDR
br-srv  IN A    $BR_SRV_ADDR
$HTTP_ALIAS     IN A    $DNS_HTTP_IP
$APP_ALIAS      IN A    $DNS_APP_IP
EOFINNER
cat > /var/lib/bind/etc/zones/113.168.192.in-addr.arpa.zone <<EOFINNER
\$TTL 3600
@ IN SOA hq-srv.$DOMAIN. admin.$DOMAIN. (2025010101 3600 900 604800 86400)
  IN NS hq-srv.$DOMAIN.
1 IN PTR hq-rtr.$DOMAIN.
2 IN PTR hq-srv.$DOMAIN.
EOFINNER
cat > /var/lib/bind/etc/zones/213.168.192.in-addr.arpa.zone <<EOFINNER
\$TTL 3600
@ IN SOA hq-srv.$DOMAIN. admin.$DOMAIN. (2025010101 3600 900 604800 86400)
  IN NS hq-srv.$DOMAIN.
11 IN PTR hq-cli.$DOMAIN.
EOFINNER
cat > /var/lib/bind/etc/zones/10.168.192.in-addr.arpa.zone <<EOFINNER
\$TTL 3600
@ IN SOA hq-srv.$DOMAIN. admin.$DOMAIN. (2025010101 3600 900 604800 86400)
  IN NS hq-srv.$DOMAIN.
1 IN PTR br-rtr.$DOMAIN.
2 IN PTR br-srv.$DOMAIN.
EOFINNER
chown -R named:named /var/lib/bind 2>/dev/null || true
cat > /etc/systemd/system/named-direct.service <<'EOFINNER'
[Unit]
Description=Direct BIND DNS Server for module 1
After=network.target
[Service]
Type=simple
ExecStart=/usr/sbin/named -g -u named -t /var/lib/bind -c /etc/named-direct.conf
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOFINNER
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
hostname
ip -br a
ip route
id "$SSH_USER"
sudo -l -U "$SSH_USER" || true
ss -tulpen | grep "$SSH_PORT" || true
systemctl is-active named-direct || true
ss -tulpen | grep ':53' || true
dig +short @127.0.0.1 "hq-srv.$DOMAIN" || true
dig +short @127.0.0.1 "$HTTP_ALIAS.$DOMAIN" || true
dig +short @127.0.0.1 "$APP_ALIAS.$DOMAIN" || true
EOF

  cat > "$ROOT/scripts/br-srv.sh" <<'EOF'
hostnamectl set-hostname BR-SRV
write_eth_static "$BR_SRV_IF" "$BR_SRV_IP" "$BR_RTR_LAN_ADDR"
cat > "/etc/net/ifaces/$BR_SRV_IF/resolv.conf" <<EOFINNER
search $DOMAIN
nameserver $HQ_SRV_ADDR
EOFINNER
cat > /etc/resolv.conf <<EOFINNER
search $DOMAIN
nameserver $DNS_FORWARDER_1
nameserver $DNS_FORWARDER_2
nameserver $DNS_FORWARDER_FALLBACK
EOFINNER
restart_network_safe
ip route replace default via "$BR_RTR_LAN_ADDR" dev "$BR_SRV_IF" || true
safe_apt_install sudo openssh-server tzdata
timedatectl set-timezone "$TZ"
id "$SSH_USER" >/dev/null 2>&1 || useradd -m -u "$SSH_UID" -s /bin/bash "$SSH_USER"
echo "$SSH_USER:$SSH_PASS" | chpasswd
mkdir -p /etc/sudoers.d /etc/ssh
echo "$SSH_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$SSH_USER"
chmod 440 "/etc/sudoers.d/$SSH_USER"
echo 'Authorized access only' > /etc/ssh/banner
SSHD_CONF="/etc/ssh/sshd_config"
[[ -f /etc/openssh/sshd_config ]] && SSHD_CONF="/etc/openssh/sshd_config"
sed -i '/^# BEGIN M1 SSH$/,/^# END M1 SSH$/d' "$SSHD_CONF"
cat >> "$SSHD_CONF" <<EOFINNER
# BEGIN M1 SSH
Port $SSH_PORT
AllowUsers $SSH_USER
MaxAuthTries 2
Banner /etc/ssh/banner
# END M1 SSH
EOFINNER
systemctl enable --now sshd
systemctl restart sshd
cat > /etc/resolv.conf <<EOFINNER
search $DOMAIN
nameserver $HQ_SRV_ADDR
EOFINNER
hostname
ip -br a
ip route
id "$SSH_USER"
sudo -l -U "$SSH_USER" || true
ss -tulpen | grep "$SSH_PORT" || true
ping -c 4 "$HQ_SRV_ADDR" || true
ping -c 4 "$DNS_FORWARDER_FALLBACK" || true
EOF

  cat > "$ROOT/scripts/hq-cli.sh" <<'EOF'
hostnamectl set-hostname HQ-CLI
write_eth_dhcp "$HQ_CLI_IF"
pkill dhcpcd 2>/dev/null || true
rm -f "/run/dhcpcd/$HQ_CLI_IF.pid"
ip addr flush dev "$HQ_CLI_IF" || true
restart_network_safe
cat > /etc/resolv.conf <<EOFINNER
search $DOMAIN
nameserver $HQ_SRV_ADDR
EOFINNER
hostname
ip -br a
ip route
cat /etc/resolv.conf
ping -c 4 "$HQ_RTR_CLI_ADDR" || true
ping -c 4 "$BR_SRV_ADDR" || true
nslookup "hq-srv.$DOMAIN" "$HQ_SRV_ADDR" || true
EOF
}

run_script() {
  local target="$1"
  local vmid
  local local_script="$ROOT/scripts/$target.sh"
  vmid="$(target_vmid "$target")"
  wait_agent "$vmid" || {
    echo "[FAIL] qemu-guest-agent unavailable for $target"
    return 1
  }
  guest_put "$target" "$vmid" "$ROOT/env.sh" "/tmp/module1-remote/env.sh"
  guest_put "$target" "$vmid" "$ROOT/common.sh" "/tmp/module1-remote/common.sh"
  guest_put "$target" "$vmid" "$local_script" "/tmp/module1-remote/$target.sh"
  guest_exec_pretty "$target" "$vmid" "configure" "set -euo pipefail; source /tmp/module1-remote/env.sh; source /tmp/module1-remote/common.sh; source /tmp/module1-remote/$target.sh"
}

set_vm_net_tag() {
  local target="$1"
  local vmid="$2"
  local net_name="$3"
  local tag="$4"
  local bridge="$5"
  local line value new_value
  line="$(qm config "$vmid" | awk -F': ' -v n="$net_name" '$1 == n {print $2}')"
  if [[ -z "$line" ]]; then
    echo "[FAIL] $target $net_name not found"
    return 1
  fi
  value="$(printf '%s\n' "$line" | sed -E 's/,tag=[0-9]+//g; s/,bridge=[^,]+//g')"
  new_value="${value},bridge=${bridge},tag=${tag}"
  if [[ "$line" == "$new_value" ]]; then
    echo "[OK] $target $net_name already tag=$tag"
  else
    qm set "$vmid" "--$net_name" "$new_value"
    echo "[OK] $target $net_name tag=$tag"
  fi
}

prepare_vlans() {
  echo "[STEP] prepare Proxmox VLAN tags"
  set_vm_net_tag hq-srv "$HQ_SRV_VMID" "$HQ_SRV_PVE_NET" "$VLAN_SRV" vmbr1003
  set_vm_net_tag hq-cli "$HQ_CLI_VMID" "$HQ_CLI_PVE_NET" "$VLAN_CLI" vmbr1003
}

check_item() {
  local label="$1"
  local vmid="$2"
  local cmd="$3"
  local tmp out err meta exitcode
  tmp="$(mktemp -d)"
  out="$tmp/out"
  err="$tmp/err"
  meta="$tmp/meta"
  guest_exec_capture "$vmid" "$cmd" "$out" "$err" "$meta"
  exitcode="$(meta_value "$meta" exitcode)"
  if [[ "$exitcode" == "0" ]]; then
    echo "[OK] $label"
  else
    echo "[FAIL] $label"
    print_block STDOUT "$out"
    print_block STDERR "$err"
    CHECK_FAILED=1
  fi
  rm -rf "$tmp"
}

check_module1() {
  CHECK_FAILED=0
  echo
  echo "============================================================"
  echo "MODULE 1 CHECK SUMMARY"
  echo "============================================================"
  echo
  check_item "ISP NAT and internet" "$ISP_VMID" "ping -c 4 8.8.8.8 >/dev/null && nft list ruleset | grep -q masquerade"
  check_item "HQ-RTR GRE tunnel" "$HQ_RTR_VMID" "ip tunnel show $GRE_NAME | grep -q '$BR_RTR_WAN_ADDR' && ping -c 4 $GRE_BR_ADDR >/dev/null"
  check_item "BR-RTR GRE tunnel" "$BR_RTR_VMID" "ip tunnel show $GRE_NAME | grep -q '$HQ_RTR_WAN_ADDR' && ping -c 4 $GRE_HQ_ADDR >/dev/null"
  check_item "HQ-RTR VLAN $VLAN_SRV/$VLAN_CLI/$VLAN_MGMT interfaces" "$HQ_RTR_VMID" "ip -br a | grep -q '$HQ_RTR_LAN_IF.$VLAN_SRV' && ip -br a | grep -q '$HQ_RTR_LAN_IF.$VLAN_CLI' && ip -br a | grep -q '$HQ_RTR_LAN_IF.$VLAN_MGMT'"
  check_item "OSPF neighbor Full on HQ-RTR" "$HQ_RTR_VMID" "vtysh -c 'show ip ospf neighbor' | grep -q Full"
  check_item "OSPF neighbor Full on BR-RTR" "$BR_RTR_VMID" "vtysh -c 'show ip ospf neighbor' | grep -q Full"
  check_item "DNS service on HQ-SRV" "$HQ_SRV_VMID" "systemctl is-active --quiet named-direct && ss -tulpen | grep -q ':53'"
  check_item "DNS records hq-srv/\$HTTP_ALIAS/\$APP_ALIAS" "$HQ_SRV_VMID" "test \"\$(dig +short @127.0.0.1 hq-srv.$DOMAIN)\" = $HQ_SRV_ADDR && test \"\$(dig +short @127.0.0.1 $HTTP_ALIAS.$DOMAIN)\" = $DNS_HTTP_IP && test \"\$(dig +short @127.0.0.1 $APP_ALIAS.$DOMAIN)\" = $DNS_APP_IP"
  check_item "SSH $SSH_PORT listens on HQ-SRV" "$HQ_SRV_VMID" "ss -tulpen | grep -q ':$SSH_PORT'"
  check_item "SSH $SSH_PORT listens on BR-SRV" "$BR_SRV_VMID" "ss -tulpen | grep -q ':$SSH_PORT'"
  check_item "HQ-SRV -> BR-SRV ping" "$HQ_SRV_VMID" "ping -c 4 $BR_SRV_ADDR >/dev/null"
  check_item "HQ-CLI -> BR-SRV ping" "$HQ_CLI_VMID" "ping -c 4 $BR_SRV_ADDR >/dev/null"
  check_item "BR-SRV -> HQ-SRV ping" "$BR_SRV_VMID" "ping -c 4 $HQ_SRV_ADDR >/dev/null"
  check_item "BR-SRV -> HQ-CLI ping" "$BR_SRV_VMID" "ping -c 4 $HQ_CLI_ADDR >/dev/null || ping -c 4 $HQ_CLI_DHCP_START >/dev/null"
  echo
  if [[ "$CHECK_FAILED" -eq 0 ]]; then
    echo "RESULT: MODULE 1 PASSED"
    return 0
  fi
  echo "RESULT: MODULE 1 FAILED"
  return 1
}

run_all() {
  prepare_vlans
  run_script isp
  run_script hq-rtr
  run_script br-rtr
  run_script hq-srv
  run_script br-srv
  run_script hq-cli
  check_module1
}

main() {
  need_root
  mkdir -p "$ROOT"
  : > "$LOG"
  exec > >(tee -a "$LOG") 2>&1
  write_guest_scripts
  case "$MODE" in
    run|"")
      run_all
      ;;
    check)
      check_module1
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
