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

set_module2_defaults() {
  : "${DOMAIN:=au-team.irpo}"
  : "${REALM:=AU-TEAM.IRPO}"
  : "${WEB_DOMAIN:=web.au-team.irpo}"
  : "${DOCKER_DOMAIN:=docker.au-team.irpo}"
  : "${AD_NETBIOS_DOMAIN:=AU-TEAM}"
  : "${SAMBA_DOMAIN:=$AD_NETBIOS_DOMAIN}"
  : "${SAMBA_REALM:=$REALM}"
  : "${SAMBA_ADMIN_USER:=Administrator}"
  : "${SAMBA_ADMIN_PASS:=${DOMAIN_PASS:-P@ssw0rd}}"
  : "${SAMBA_DC_HOST:=br-srv.$DOMAIN}"
  : "${SAMBA_DC_IP:=${BR_SRV_ADDR:-192.168.10.2}}"
  : "${SAMBA_GROUP:=${DOMAIN_GROUP:-hq}}"
  : "${SAMBA_USER_PREFIX:=${DOMAIN_USERS_PREFIX:-hquser}}"
  : "${SAMBA_USERS_COUNT:=${DOMAIN_USERS_COUNT:-5}}"
  : "${AD_USERS_CSV:=/mnt/additional/Users.csv}"
  : "${ADDITIONAL_MOUNT:=/mnt/additional}"
  : "${ADDITIONAL_CDROM_1:=/dev/sr0}"
  : "${ADDITIONAL_CDROM_2:=/dev/cdrom}"
  : "${RAID_DEVICE:=/dev/md3}"
  : "${RAID_LEVEL:=5}"
  : "${RAID_DISK_COUNT:=3}"
  : "${RAID_DISK_SIZE_GB:=1}"
  : "${RAID_MOUNT:=/raid}"
  : "${NFS_DIR:=/raid/nfs}"
  : "${NFS_EXPORT_DIR:=$NFS_DIR}"
  : "${NFS_CLIENT_MOUNT:=/mnt/nfs}"
  : "${NFS_MOUNT_DIR:=$NFS_CLIENT_MOUNT}"
  : "${NFS_SERVER:=${HQ_SRV_ADDR:-192.168.113.2}}"
  : "${NFS_CLIENT_NET:=192.168.213.0/27}"
  : "${NTP_SERVER_ROLE:=ISP}"
  : "${NTP_STRATUM:=8}"
  : "${ANSIBLE_WORKDIR:=/etc/ansible}"
  : "${ANSIBLE_REPORT_DIR:=/etc/ansible/PC-INFO}"
  : "${ANSIBLE_PLAYBOOK_SRC:=/mnt/additional/playbook/get_hostname_address.yml}"
  : "${DOCKER_APP_IMAGE:=site:latest}"
  : "${DOCKER_DB_IMAGE:=postgres:15-alpine}"
  : "${DOCKER_NETWORK:=examnet}"
  : "${DOCKER_APP_CONTAINER:=site}"
  : "${DOCKER_SITE_CONTAINER:=$DOCKER_APP_CONTAINER}"
  : "${DOCKER_DB_CONTAINER:=db}"
  : "${DOCKER_DB_NAME:=testdb3}"
  : "${DOCKER_DB_USER:=test3c}"
  : "${DOCKER_DB_PASS:=P@ssw0rd}"
  : "${DOCKER_APP_PORT:=8083}"
  : "${DOCKER_CONTAINER_PORT:=8000}"
  : "${DOCKER_SITE_IMAGE:=$DOCKER_APP_IMAGE}"
  : "${APP_PORT:=$DOCKER_APP_PORT}"
  : "${WEB_DB_NAME:=webdb}"
  : "${WEB_DB_USER:=web3}"
  : "${WEB_DB_PASS:=P@ssw0rd}"
  : "${WEB_DOCROOT:=/var/www/html}"
  : "${WEB_ROOT:=$WEB_DOCROOT}"
  : "${WEB_HTTP_SERVICE:=httpd2}"
  : "${WEB_DB_SERVICE:=mariadb}"
  : "${WEB_HTTP_PORT:=80}"
  : "${NGINX_SERVICE:=nginx}"
  : "${BASIC_AUTH_USER:=Kazimirc}"
  : "${BASIC_AUTH_PASS:=P@ssw0rd}"
  : "${BASIC_AUTH_FILE:=/etc/nginx/.htpasswd}"
  : "${YANDEX_BROWSER_PACKAGE:=yandex-browser-stable}"
  : "${YANDEX_BROWSER_PREINSTALL_PACKAGE:=yandex-browser-preinstall}"
  : "${YANDEX_BROWSER_BIN:=/usr/bin/yandex-browser-stable}"
  : "${DOMAIN_USERS_PREFIX:=hquser}"
  : "${DOMAIN_USERS_SUFFIX:=}"
  : "${DOMAIN_USERS_COUNT:=5}"
  : "${DOMAIN_GROUP:=hq}"
  : "${DOMAIN_PASS:=P@ssw0rd}"
  : "${NET_ADMIN_USER:=${ROUTER_ADMIN_USER:-net_admin}}"
  : "${NET_ADMIN_PASS:=${ROUTER_ADMIN_PASS:-P@ssw0rd}}"
  : "${SSH_USER:=sshuser}"
  : "${SSH_PASS:=P@ssw0rd}"
  : "${SSH_PORT:=2013}"
  : "${DNS_WEB_IP:=172.16.50.1}"
  : "${DNS_DOCKER_IP:=172.16.60.1}"
}

set_module2_defaults
