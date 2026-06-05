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

service_restart_enable() {
  local svc
  for svc in "$@"; do
    if systemctl cat "$svc" >/dev/null 2>&1; then
      systemctl enable "$svc" || true
      systemctl restart "$svc"
      return 0
    fi
  done
  return 1
}

ensure_samba_a_record() {
  local name="$1"
  local addr="$2"
  local old_addr
  shift 2
  for old_addr in "$@" "$addr"; do
    samba-tool dns delete 127.0.0.1 "$DOMAIN" "$name" A "$old_addr" -U "Administrator%$DOMAIN_PASS" 2>/dev/null || true
  done
  samba-tool dns add 127.0.0.1 "$DOMAIN" "$name" A "$addr" -U "Administrator%$DOMAIN_PASS" 2>/dev/null || true
  samba-tool dns query 127.0.0.1 "$DOMAIN" "$name" A -U "Administrator%$DOMAIN_PASS" | grep -q "$addr"
}

host="$(hostname | tr '[:upper:]' '[:lower:]')"

case "$host" in
  br-srv*)
    safe_apt_install samba samba-dc samba-client samba-winbind-clients samba-winbind-common krb5-kinit bind-utils
    test -x /usr/sbin/samba
    test -x /usr/bin/samba-tool
    test -x /usr/bin/smbclient
    test -x /usr/bin/kinit

    hostnamectl set-hostname "br-srv.$DOMAIN" || true
    cat > /etc/hosts <<EOFINNER
127.0.0.1 localhost
$BR_SRV_ADDR br-srv.$DOMAIN br-srv BR-SRV
EOFINNER

    if ! samba-tool domain info 127.0.0.1 >/dev/null 2>&1; then
      systemctl disable --now smb nmb winbind 2>/dev/null || true
      if [[ -d /etc/samba && ! -d /etc/samba.pre-module2 ]]; then
        cp -a /etc/samba /etc/samba.pre-module2
      fi
      rm -f /etc/samba/smb.conf
      samba-tool domain provision \
        --use-rfc2307 \
        --realm="$REALM" \
        --domain="$AD_NETBIOS_DOMAIN" \
        --server-role=dc \
        --dns-backend=SAMBA_INTERNAL \
        --adminpass="$DOMAIN_PASS"
      cp /var/lib/samba/private/krb5.conf /etc/krb5.conf
    else
      echo "[OK] Samba domain already provisioned"
    fi

    cat > /etc/resolv.conf <<EOFINNER
nameserver 127.0.0.1
nameserver $HQ_SRV_ADDR
search $DOMAIN
domain $DOMAIN
EOFINNER

    service_restart_enable samba samba-ad-dc

    ensure_samba_a_record br-srv "$BR_SRV_ADDR" 172.17.0.1 172.18.0.1
    ensure_samba_a_record hq-srv "$HQ_SRV_ADDR" 192.168.100.2
    ensure_samba_a_record hq-rtr "$HQ_RTR_SRV_ADDR" 192.168.100.1
    ensure_samba_a_record hq-cli "$HQ_CLI_ADDR" 192.168.200.10 192.168.200.11 192.168.213.10
    ensure_samba_a_record br-rtr "$BR_RTR_LAN_ADDR"
    ensure_samba_a_record web "$DNS_WEB_IP" 172.16.1.1
    ensure_samba_a_record docker "$DNS_DOCKER_IP" 172.16.2.1

    samba-tool group show "$DOMAIN_GROUP" >/dev/null 2>&1 || samba-tool group add "$DOMAIN_GROUP"
    for i in $(seq 1 "$DOMAIN_USERS_COUNT"); do
      user="${DOMAIN_USERS_PREFIX}${i}${DOMAIN_USERS_SUFFIX}"
      samba-tool user show "$user" >/dev/null 2>&1 || samba-tool user create "$user" "$DOMAIN_PASS"
      samba-tool group addmembers "$DOMAIN_GROUP" "$user" 2>/dev/null || true
    done

    samba-tool domain info 127.0.0.1
    host -t SRV "_ldap._tcp.$DOMAIN" 127.0.0.1 || true
    host -t SRV "_kerberos._udp.$DOMAIN" 127.0.0.1 || true
    printf '%s\n' "$DOMAIN_PASS" | kinit Administrator || true
    klist || true
    samba-tool user list | grep "$DOMAIN_USERS_PREFIX" || true
    samba-tool group listmembers "$DOMAIN_GROUP" || true
    wbinfo -u | grep "$DOMAIN_USERS_PREFIX" || true
    echo "[OK] Samba AD DC configured on BR-SRV"
    ;;

  hq-cli*)
    safe_apt_install samba samba-client samba-winbind samba-winbind-clients samba-winbind-common krb5-kinit bind-utils sudo openssh-server python3
    command -v winbindd >/dev/null
    command -v wbinfo >/dev/null
    command -v net >/dev/null
    command -v kinit >/dev/null

    systemctl stop winbind 2>/dev/null || true
    net ads leave -U "Administrator%$DOMAIN_PASS" 2>/dev/null || true
    rm -f /var/lib/samba/private/secrets.tdb
    rm -f /var/lib/samba/private/secrets.ldb
    rm -f /etc/krb5.keytab

    cat > /etc/resolv.conf <<EOFINNER
search $DOMAIN
domain $DOMAIN
nameserver $BR_SRV_ADDR
nameserver $HQ_SRV_ADDR
EOFINNER

    cat > /etc/krb5.conf <<EOFINNER
[libdefaults]
    default_realm = $REALM
    dns_lookup_realm = false
    dns_lookup_kdc = true
EOFINNER

    mkdir -p /etc/samba
    cat > /etc/samba/smb.conf <<EOFINNER
[global]
    workgroup = $AD_NETBIOS_DOMAIN
    realm = $REALM
    security = ADS
    kerberos method = secrets and keytab
    dedicated keytab file = /etc/krb5.keytab
    winbind use default domain = yes
    winbind enum users = yes
    winbind enum groups = yes
    idmap config * : backend = tdb
    idmap config * : range = 3000-7999
    idmap config $AD_NETBIOS_DOMAIN : backend = rid
    idmap config $AD_NETBIOS_DOMAIN : range = 10000-999999
    template shell = /bin/bash
    template homedir = /home/%U
EOFINNER

    printf '%s\n' "$DOMAIN_PASS" | kinit Administrator
    net ads join -U "Administrator%$DOMAIN_PASS"

    systemctl enable --now winbind || service_restart_enable winbind winbindd
    systemctl restart winbind || systemctl restart winbindd || true

    sed -i 's/^passwd:.*/passwd: files winbind systemd/' /etc/nsswitch.conf || true
    sed -i 's/^group:.*/group: files winbind systemd/' /etc/nsswitch.conf || true

    mkdir -p /etc/sudoers.d
    cat > /etc/sudoers.d/domain-hq-limited <<EOFINNER
%$DOMAIN_GROUP ALL=(root) NOPASSWD: /usr/bin/id, /bin/id, /usr/bin/cat, /bin/cat, /usr/bin/grep, /bin/grep
EOFINNER
    chmod 440 /etc/sudoers.d/domain-hq-limited
    visudo -cf /etc/sudoers.d/domain-hq-limited

    net ads testjoin
    wbinfo -t
    wbinfo -u | grep "$DOMAIN_USERS_PREFIX"
    wbinfo -g | grep "$DOMAIN_GROUP"
    getent passwd "${DOMAIN_USERS_PREFIX}1${DOMAIN_USERS_SUFFIX}"
    id "${DOMAIN_USERS_PREFIX}1${DOMAIN_USERS_SUFFIX}"
    sudo -l -U "${DOMAIN_USERS_PREFIX}1${DOMAIN_USERS_SUFFIX}"
    echo "[OK] HQ-CLI joined to Samba domain"
    ;;

  *)
    echo "[FAIL] Unsupported Samba target host: $host"
    echo "Command: hostname"
    echo "Next hint: run module2-samba only on BR-SRV and HQ-CLI"
    exit 1
    ;;
esac
