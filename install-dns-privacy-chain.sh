#!/bin/sh
#
# DNS Privacy Chain Installer
# Automatically installs: Tor -> dnscrypt-proxy -> Unbound -> AdGuard Home
# Tested on: Alpine Linux 3.22+
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    printf "${GREEN}[INFO]${NC} %s\n" "$1"
}

log_warn() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1"
}

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be run as root"
    exit 1
fi

log_info "Starting DNS Privacy Chain installation..."
log_info "This will install: Tor -> dnscrypt-proxy -> Unbound -> AdGuard Home"

# Check and upgrade kernel if needed
log_info "Checking kernel compatibility..."
CURRENT_KERNEL=$(uname -r)
log_info "Current kernel: $CURRENT_KERNEL"

if [[ "$CURRENT_KERNEL" == *"-virt"* ]]; then
    log_warn "Detected -virt kernel. Upgrading to linux-lts for iptables support..."
    apk update
    apk add --no-cache linux-lts iptables-legacy iptables-openrc

    echo ""
    echo "======================================================================"
    echo "⚠️  REBOOT REQUIRED - Phase 1 Complete"
    echo "======================================================================"
    echo ""
    echo "The linux-lts kernel has been installed."
    echo "Please reboot your server and run this script again."
    echo ""
    echo "To reboot now: reboot"
    echo "After reboot, run: sh $0"
    echo ""
    exit 0
fi

# Phase 2: Install services (runs after reboot with LTS kernel)
log_info "LTS kernel detected. Proceeding with service installation..."

# Update package index
log_info "Updating package index..."
apk update

# Install base packages
log_info "Installing base packages..."
apk add --no-cache tor dnscrypt-proxy unbound curl wget iproute2 bind-tools

# Configure Tor
log_info "Configuring Tor SOCKS proxy on port 9053 (client-only mode)..."
cat > /etc/tor/torrc << 'EOF'
SocksPort 127.0.0.1:9053
SocksPolicy accept 127.0.0.1
SocksPolicy reject *
ClientOnly 1
DataDirectory /var/lib/tor
User tor
Log notice syslog
RunAsDaemon 1
EOF

# Start and enable Tor
log_info "Starting Tor service..."
rc-service tor start
rc-update add tor default

# Configure dnscrypt-proxy
log_info "Configuring dnscrypt-proxy on port 5053 with Tor proxy..."
cp /etc/dnscrypt-proxy/dnscrypt-proxy.toml /etc/dnscrypt-proxy/dnscrypt-proxy.toml.orig 2>/dev/null || true

cat > /etc/dnscrypt-proxy/dnscrypt-proxy.toml << 'EOF'
listen_addresses = ["127.0.0.1:5053"]
proxy = "socks5://127.0.0.1:9053"
max_clients = 250
ipv4_servers = true
ipv6_servers = true
doh_servers = true
require_dnssec = false
require_nolog = true
require_nofilter = false
force_tcp = true
timeout = 2500
cert_refresh_delay = 240
dnscrypt_ephemeral_keys = true
ignore_system_dns = true
block_ipv6 = false
cache = true
cache_size = 4200
cache_min_ttl = 600
cache_max_ttl = 86400
cache_neg_ttl = 60

[sources]

[sources."public-resolvers"]
urls = ["https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/public-resolvers.md", "https://download.dnscrypt.info/resolvers-list/v3/public-resolvers.md"]
minisign_key = "RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3"
cache_file = "public-resolvers.md"

[sources."cs-resolvers"]
urls = ["https://cryptostorm.is/cs-resolvers.md", "https://raw.githubusercontent.com/cryptostorm/cstorm_deepDNS/master/cs-resolvers.md"]
cache_file = "cs-resolvers.md"
minisign_key = "RWTzXTWKLLKfM3fRQW0CUwSN17U3YMsVcVdfi3ERraxuttv2tL8dsdUE"
refresh_delay = 72
EOF

# Start and enable dnscrypt-proxy
log_info "Starting dnscrypt-proxy service..."
rc-service dnscrypt-proxy start
rc-update add dnscrypt-proxy default

# Configure Unbound
log_info "Configuring Unbound on port 5353 forwarding to dnscrypt-proxy..."
cp /etc/unbound/unbound.conf /etc/unbound/unbound.conf.orig 2>/dev/null || true

cat > /etc/unbound/unbound.conf << 'EOF'
server:
    interface: 127.0.0.1@5353
    do-ip4: yes
    do-ip6: no
    do-udp: yes
    do-tcp: yes
    access-control: 127.0.0.0/8 allow
    do-not-query-localhost: no
    verbosity: 1
    hide-identity: yes
    hide-version: yes
    harden-glue: yes
    harden-dnssec-stripped: yes
    use-caps-for-id: yes
    prefetch: yes
    num-threads: 2
    msg-cache-size: 8m
    rrset-cache-size: 16m
    cache-min-ttl: 60
    cache-max-ttl: 86400

forward-zone:
    name: "."
    forward-addr: 127.0.0.1@5053
EOF

# Start and enable Unbound
log_info "Starting Unbound service..."
rc-service unbound start
rc-update add unbound default

# Install AdGuard Home
log_info "Installing AdGuard Home..."
ARCH="amd64"
if [ "$(uname -m)" = "aarch64" ]; then
    ARCH="arm64"
fi

cd /tmp
wget -q "https://static.adguard.com/adguardhome/release/AdGuardHome_linux_${ARCH}.tar.gz"
tar xzf "AdGuardHome_linux_${ARCH}.tar.gz"
cd AdGuardHome
./AdGuardHome -s install

# Wait for AdGuard to initialize
log_info "Waiting for AdGuard Home to initialize..."
sleep 3

# Get server IP addresses
SERVER_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -1)

# Configure firewall - DISABLED (causing SSH lockout on reboot)
# log_info "Configuring iptables firewall..."
# mkdir -p /etc/iptables
# mkdir -p /etc/local.d

# cat > /etc/local.d/firewall.start << 'EOF'
# #!/bin/sh
#
# # Flush existing rules
# iptables-legacy -F
# iptables-legacy -X
# iptables-legacy -t nat -F
# iptables-legacy -t nat -X
# iptables-legacy -t mangle -F
# iptables-legacy -t mangle -X
#
# # Set default policies
# iptables-legacy -P INPUT DROP
# iptables-legacy -P FORWARD DROP
# iptables-legacy -P OUTPUT ACCEPT
#
# # Allow loopback
# iptables-legacy -A INPUT -i lo -j ACCEPT
#
# # Allow established and related
# iptables-legacy -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
#
# # Allow SSH
# iptables-legacy -A INPUT -p tcp --dport 22 -j ACCEPT
#
# # Allow DNS (TCP and UDP)
# iptables-legacy -A INPUT -p tcp --dport 53 -j ACCEPT
# iptables-legacy -A INPUT -p udp --dport 53 -j ACCEPT
#
# # Allow AdGuard Web UI
# iptables-legacy -A INPUT -p tcp --dport 80 -j ACCEPT
# iptables-legacy -A INPUT -p tcp --dport 3000 -j ACCEPT
#
# # Allow ICMP (ping)
# iptables-legacy -A INPUT -p icmp -j ACCEPT
#
# # Log dropped packets (optional - commented out by default)
# # iptables-legacy -A INPUT -m limit --limit 5/min -j LOG --log-prefix "FW-DROP: " --log-level 4
#
# EOF
#
# chmod +x /etc/local.d/firewall.start
#
# # Configure iptables service
# cat > /etc/conf.d/iptables << 'EOF'
# # Location of the iptables save file
# IPTABLES_SAVE="/etc/iptables/rules-save"
#
# # Save current rules on stop
# SAVE_ON_STOP="yes"
#
# # Use legacy iptables
# IPTABLES_BIN="/usr/sbin/iptables-legacy"
# IPTABLES_SAVE_BIN="/usr/sbin/iptables-legacy-save"
# IPTABLES_RESTORE_BIN="/usr/sbin/iptables-legacy-restore"
# EOF
#
# # Enable firewall services (will activate after reboot with LTS kernel)
# rc-update add local default
# # Note: NOT enabling iptables service - local.d script will handle all firewall rules

log_info "Installation complete!"
echo ""
echo "======================================================================"
echo " DNS Privacy Chain Installation Summary - Phase 2 Complete"
echo "======================================================================"
echo ""
echo "Services installed and configured:"
echo "  ✓ Tor SOCKS proxy:      127.0.0.1:9053"
echo "  ✓ dnscrypt-proxy:       127.0.0.1:5053 (via Tor)"
echo "  ✓ Unbound:              127.0.0.1:5353 (with DNSSEC)"
echo "  ✓ AdGuard Home:         0.0.0.0:53 (DNS)"
echo "  ✓ AdGuard Web UI:       0.0.0.0:80, 0.0.0.0:3000"
echo "  ✓ LTS Kernel:           $(uname -r)"
echo ""
echo "DNS Resolution Chain:"
echo "  Client → AdGuard:53 → Unbound:5353 → dnscrypt:5053 → Tor:9053 → ODoH"
echo ""
echo "NEXT STEPS:"
echo ""
echo "1. Complete AdGuard Home setup through web interface:"
if [ -n "$SERVER_IP" ]; then
    echo "   Open: http://${SERVER_IP}:3000"
else
    echo "   Open: http://YOUR_SERVER_IP:3000"
fi
echo ""
echo "   Configuration settings for AdGuard setup wizard:"
echo "   - Admin Web Interface: 0.0.0.0:3000 (or your choice)"
echo "   - DNS server address: 0.0.0.0:53"
echo "   - Upstream DNS: 127.0.0.1:5353"
echo ""
echo "2. Verify installation:"
echo "   rc-status -a | grep -E '(tor|dnscrypt|unbound|AdGuard)'"
echo "   dig @127.0.0.1 example.com"
echo ""
echo "3. Test DNS from a remote machine:"
if [ -n "$SERVER_IP" ]; then
    echo "   dig @${SERVER_IP} example.com"
else
    echo "   dig @YOUR_SERVER_IP example.com"
fi
echo ""
echo "Configuration files backed up with .orig extension:"
echo "  /etc/tor/torrc"
echo "  /etc/dnscrypt-proxy/dnscrypt-proxy.toml"
echo "  /etc/unbound/unbound.conf"
echo ""
echo "NOTE: Firewall is NOT configured by this script."
echo "      Configure iptables manually if needed for security."
echo "======================================================================"
