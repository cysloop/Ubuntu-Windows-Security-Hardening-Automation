#!/bin/bash

set -e

# ==============================
# Ubuntu Server Setup Script
# ==============================

GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m"

echo "=========================================="
echo " Ubuntu Server Security & Network Setup"
echo "=========================================="
echo

# ------------------------------
# 1. Root Check
# ------------------------------

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run this script as root.${NC}"
    exit 1
fi

# ------------------------------
# 2. Detect Network Interface
# ------------------------------

INTERFACE=$(ip route | awk '/default/ {print $5; exit}')

if [ -z "$INTERFACE" ]; then
    INTERFACE=$(ip -o link show | awk -F': ' '$2 != "lo" {print $2; exit}')
fi

if [ -z "$INTERFACE" ]; then
    echo -e "${RED}Could not detect network interface.${NC}"
    exit 1
fi

echo -e "${GREEN}Network Interface:${NC} $INTERFACE"

# ------------------------------
# 3. Detect Current Prefix
# ------------------------------

CURRENT_PREFIX=$(ip -o -4 addr show dev "$INTERFACE" | awk '{print $4}' | cut -d/ -f2 | head -n1)

if [ -z "$CURRENT_PREFIX" ]; then
    CURRENT_PREFIX="24"
fi

PREFIX="$CURRENT_PREFIX"

# ------------------------------
# 4. Detect Gateway
# ------------------------------

GATEWAY=$(ip route | awk '/default/ {print $3; exit}')

if [ -z "$GATEWAY" ]; then
    echo -e "${RED}Could not detect default gateway.${NC}"
    exit 1
fi

echo -e "${GREEN}Gateway:${NC} $GATEWAY"
echo -e "${GREEN}Prefix:${NC} /$PREFIX"

# ------------------------------
# 5. Detect DNS
# ------------------------------

DNS1=$(resolvectl dns "$INTERFACE" 2>/dev/null | \
       awk '{for(i=2;i<=NF;i++) print $i}' | head -n1)

if [ -z "$DNS1" ]; then
    DNS1="$GATEWAY"
fi

echo -e "${GREEN}DNS:${NC} $DNS1"

# ------------------------------
# 6. IPv4 Validation Function
# ------------------------------

validate_ipv4() {
    local ip="$1"

    if [[ ! "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        return 1
    fi

    IFS='.' read -r a b c d <<< "$ip"

    for octet in "$a" "$b" "$c" "$d"; do
        if ((octet < 0 || octet > 255)); then
            return 1
        fi
    done

    return 0
}

# ------------------------------
# 7. Server IP
# ------------------------------

while true; do
    read -rp "Enter Server IP: " SERVER_IP

    if ! validate_ipv4 "$SERVER_IP"; then
        echo -e "${RED}Invalid IPv4 address.${NC}"
        continue
    fi

    if [ "$SERVER_IP" = "$GATEWAY" ]; then
        echo -e "${RED}Server IP cannot be the same as Gateway.${NC}"
        continue
    fi

    break
done

# ------------------------------
# 8. SSH Allowed IP
# ------------------------------

while true; do
    read -rp "Enter SSH Allowed IP: " SSH_IP

    if ! validate_ipv4 "$SSH_IP"; then
        echo -e "${RED}Invalid IPv4 address.${NC}"
        continue
    fi

    break
done

# ------------------------------
# 9. Configuration Summary
# ------------------------------

echo
echo "=========================================="
echo " Configuration Summary"
echo "=========================================="
echo "Interface       : $INTERFACE"
echo "Server IP       : $SERVER_IP/$PREFIX"
echo "Gateway         : $GATEWAY"
echo "DNS             : $DNS1"
echo "SSH Allowed IP  : $SSH_IP"
echo "SSH Port        : 22"
echo "=========================================="
echo

read -rp "Type YES to continue: " CONFIRM

if [ "$CONFIRM" != "YES" ]; then
    echo "Cancelled."
    exit 0
fi

# ------------------------------
# 10. Backup
# ------------------------------

BACKUP_DIR="/root/server-setup-backup-$(date +%Y%m%d-%H%M%S)"

mkdir -p "$BACKUP_DIR"

echo
echo -e "${YELLOW}[1/12] Creating backup...${NC}"

cp -a /etc/netplan "$BACKUP_DIR/netplan" 2>/dev/null || true
cp -a /etc/ufw "$BACKUP_DIR/ufw" 2>/dev/null || true
cp -a /etc/fail2ban "$BACKUP_DIR/fail2ban" 2>/dev/null || true

# ------------------------------
# 11. Netplan Configuration
# ------------------------------

echo -e "${YELLOW}[2/12] Configuring static IP...${NC}"

NETPLAN_FILE="/etc/netplan/01-static-network.yaml"

cat > "$NETPLAN_FILE" <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $INTERFACE:
      dhcp4: false
      dhcp6: false
      addresses:
        - $SERVER_IP/$PREFIX
      routes:
        - to: default
          via: $GATEWAY
      nameservers:
        addresses:
          - $DNS1
          - 1.1.1.1
EOF

chmod 600 "$NETPLAN_FILE"

# ------------------------------
# 12. Validate Netplan
# ------------------------------

echo -e "${YELLOW}[3/12] Validating Netplan...${NC}"

if ! netplan generate; then
    echo -e "${RED}Netplan configuration is invalid.${NC}"
    rm -f "$NETPLAN_FILE"
    exit 1
fi

echo
echo -e "${YELLOW}Testing network configuration...${NC}"
echo "If the connection works, confirm the Netplan prompt."

if ! netplan try --timeout 120; then
    echo -e "${RED}Netplan test failed. Restoring backup...${NC}"

    rm -f "$NETPLAN_FILE"

    if [ -d "$BACKUP_DIR/netplan" ]; then
        rm -rf /etc/netplan
        cp -a "$BACKUP_DIR/netplan" /etc/netplan
    fi

    netplan generate
    netplan apply

    exit 1
fi

# ------------------------------
# 13. Verify Network
# ------------------------------

echo -e "${YELLOW}[4/12] Verifying network...${NC}"

if ! ip -4 addr show dev "$INTERFACE" | grep -q "$SERVER_IP"; then
    echo -e "${RED}Server IP was not applied correctly.${NC}"
    exit 1
fi

if ! ip route | grep -q "default via $GATEWAY"; then
    echo -e "${RED}Default gateway was not applied correctly.${NC}"
    exit 1
fi

echo -e "${GREEN}Network configuration OK.${NC}"

# ------------------------------
# 14. Update System
# ------------------------------

echo -e "${YELLOW}[5/12] Updating system...${NC}"

apt update
apt upgrade -y

# ------------------------------
# 15. Install SSH
# ------------------------------

echo -e "${YELLOW}[6/12] Installing SSH Server...${NC}"

apt install -y openssh-server

systemctl enable ssh
systemctl restart ssh

if ! sshd -t; then
    echo -e "${RED}SSH configuration test failed.${NC}"
    exit 1
fi

if ! systemctl is-active --quiet ssh; then
    echo -e "${RED}SSH service is not running.${NC}"
    exit 1
fi

# ------------------------------
# 16. Configure UFW
# ------------------------------

echo -e "${YELLOW}[7/12] Configuring UFW Firewall...${NC}"

apt install -y ufw

ufw --force reset

ufw default deny incoming
ufw default allow outgoing

ufw allow from "$SSH_IP" to any port 22 proto tcp

ufw --force enable

if ! ufw status | grep -q "22/tcp"; then
    echo -e "${RED}SSH firewall rule was not created.${NC}"
    exit 1
fi

# ------------------------------
# 17. Install Fail2ban
# ------------------------------

echo -e "${YELLOW}[8/12] Installing Fail2ban...${NC}"

apt install -y fail2ban python3-systemd

cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5
backend = systemd

[sshd]
enabled = true
port = 22
EOF

# ------------------------------
# 18. Test Fail2ban
# ------------------------------

echo -e "${YELLOW}[9/12] Testing Fail2ban configuration...${NC}"

if ! fail2ban-client -t; then
    echo -e "${RED}Fail2ban configuration test failed.${NC}"
    exit 1
fi

systemctl enable fail2ban
systemctl restart fail2ban

if ! systemctl is-active --quiet fail2ban; then
    echo -e "${RED}Fail2ban service is not running.${NC}"
    exit 1
fi

# ------------------------------
# 19. Automatic Security Updates
# ------------------------------

echo -e "${YELLOW}[10/12] Configuring automatic updates...${NC}"

apt install -y unattended-upgrades apt-listchanges

cat > /etc/apt/apt.conf.d/20auto-upgrades <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

dpkg-reconfigure -f noninteractive unattended-upgrades

systemctl enable apt-daily.timer
systemctl enable apt-daily-upgrade.timer

# ------------------------------
# 20. Final Verification Report
# ------------------------------

echo
echo "======================================================"
echo "              FINAL CONFIGURATION REPORT"
echo "======================================================"

# ------------------------------
# Network
# ------------------------------

echo
echo "[ NETWORK ]"

if ip -4 addr show dev "$INTERFACE" | grep -q "$SERVER_IP"; then
    echo "Server IP          : $SERVER_IP/$PREFIX  [OK]"
else
    echo "Server IP          : $SERVER_IP/$PREFIX  [FAILED]"
fi

if ip route | grep -q "default via $GATEWAY"; then
    echo "Gateway            : $GATEWAY  [OK]"
else
    echo "Gateway            : $GATEWAY  [FAILED]"
fi

if [ -n "$DNS1" ]; then
    echo "DNS                : $DNS1  [CONFIGURED]"
else
    echo "DNS                : NOT CONFIGURED  [FAILED]"
fi

echo "Network Interface  : $INTERFACE  [OK]"
echo "Prefix             : /$PREFIX  [DETECTED]"

# ------------------------------
# SSH
# ------------------------------

echo
echo "[ SSH ]"

if systemctl is-active --quiet ssh; then
    echo "SSH Service        : ENABLED / RUNNING  [OK]"
else
    echo "SSH Service        : DISABLED / STOPPED  [FAILED]"
fi

if systemctl is-enabled --quiet ssh; then
    echo "SSH Auto Start     : ENABLED  [OK]"
else
    echo "SSH Auto Start     : DISABLED  [FAILED]"
fi

echo "SSH Port           : 22"
echo "SSH Allowed IP     : $SSH_IP"

if ss -lnt | grep -q ':22 '; then
    echo "Port 22 Listening  : YES  [OK]"
else
    echo "Port 22 Listening  : NO  [FAILED]"
fi

# ------------------------------
# UFW Firewall
# ------------------------------

echo
echo "[ UFW FIREWALL ]"

if ufw status | grep -q "Status: active"; then
    echo "UFW Firewall       : ENABLED  [OK]"
else
    echo "UFW Firewall       : DISABLED  [FAILED]"
fi

if ufw status | grep -q "22/tcp"; then
    echo "SSH Rule           : ALLOWED  [OK]"
else
    echo "SSH Rule           : NOT FOUND  [FAILED]"
fi

echo "Incoming Policy    : DENY"
echo "Outgoing Policy    : ALLOW"

# ------------------------------
# Fail2ban
# ------------------------------

echo
echo "[ FAIL2BAN ]"

if systemctl is-active --quiet fail2ban; then
    echo "Fail2ban Service   : ENABLED / RUNNING  [OK]"
else
    echo "Fail2ban Service   : DISABLED / STOPPED  [FAILED]"
fi

if fail2ban-client status sshd >/dev/null 2>&1; then
    echo "SSH Jail           : ENABLED  [OK]"
else
    echo "SSH Jail           : DISABLED  [FAILED]"
fi

echo "Ban Time           : 1 hour"
echo "Find Time          : 10 minutes"
echo "Max Retry          : 5"

# ------------------------------
# Automatic Updates
# ------------------------------

echo
echo "[ AUTOMATIC UPDATES ]"

if systemctl is-enabled --quiet apt-daily.timer; then
    echo "Package Lists      : ENABLED  [OK]"
else
    echo "Package Lists      : DISABLED  [FAILED]"
fi

if systemctl is-enabled --quiet apt-daily-upgrade.timer; then
    echo "Security Updates   : ENABLED  [OK]"
else
    echo "Security Updates   : DISABLED  [FAILED]"
fi

# ------------------------------
# Netplan
# ------------------------------

echo
echo "[ NETPLAN ]"

if netplan generate >/dev/null 2>&1; then
    echo "Configuration      : VALID  [OK]"
else
    echo "Configuration      : INVALID  [FAILED]"
fi

if [ -f "$NETPLAN_FILE" ]; then
    echo "Static Config      : CREATED  [OK]"
else
    echo "Static Config      : NOT FOUND  [FAILED]"
fi

# ------------------------------
# Backup
# ------------------------------

echo
echo "[ BACKUP ]"

if [ -d "$BACKUP_DIR" ]; then
    echo "Backup             : CREATED  [OK]"
    echo "Location           : $BACKUP_DIR"
else
    echo "Backup             : NOT FOUND  [FAILED]"
fi

# ------------------------------
# Final Summary
# ------------------------------

echo
echo "======================================================"
echo "                    FINAL SUMMARY"
echo "======================================================"

echo
echo "Server IP          : $SERVER_IP/$PREFIX"
echo "SSH Allowed IP     : $SSH_IP"
echo "Gateway            : $GATEWAY"
echo "DNS                : $DNS1"
echo "Interface          : $INTERFACE"
echo "SSH Port           : 22"

echo
echo "Services:"

if systemctl is-active --quiet ssh; then
    echo "SSH                : ENABLED"
else
    echo "SSH                : DISABLED"
fi

if systemctl is-active --quiet fail2ban; then
    echo "Fail2ban            : ENABLED"
else
    echo "Fail2ban            : DISABLED"
fi

if ufw status | grep -q "Status: active"; then
    echo "UFW                 : ENABLED"
else
    echo "UFW                 : DISABLED"
fi

if systemctl is-enabled --quiet apt-daily-upgrade.timer; then
    echo "Automatic Updates   : ENABLED"
else
    echo "Automatic Updates   : DISABLED"
fi

echo
echo "Backup Location:"
echo "$BACKUP_DIR"

echo
echo "SSH Command:"
echo "ssh <username>@$SERVER_IP"

echo
echo "======================================================"
echo "             SETUP VERIFICATION COMPLETE"
echo "======================================================"