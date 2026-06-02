hostnamectl set-hostname HQ-CLI

write_eth_dhcp "$HQ_CLI_IF"
restart_network_safe

safe_apt_install tzdata
timedatectl set-timezone "$TZ"

basic_check
cat /etc/resolv.conf || true
