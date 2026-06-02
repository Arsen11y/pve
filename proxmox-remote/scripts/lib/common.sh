# common.sh — функции, выполняющиеся внутри гостевой ALT Linux ВМ.

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

basic_check() {
  hostname || true
  ip -br a || true
  ip route || true
}
