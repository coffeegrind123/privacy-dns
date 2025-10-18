# DNS Privacy Chain - Automated Installer

Single-script automated installer for a complete DNS privacy chain on Alpine Linux VPS. No Docker required.

## 🔒 What This Installs

**Complete 7-Layer DNS Privacy Chain:**
```
Your Device → AdGuard Home:53 → Unbound:5353 → dnscrypt-proxy:5053 → Tor:9053 → Tor Network → ODoH Resolvers
```

**Components:**
- **AdGuard Home** (port 53) - DNS-based ad blocking and filtering with web UI
- **Unbound** (port 5353) - Recursive DNS resolver with DNSSEC validation and caching
- **dnscrypt-proxy** (port 5053) - DNS-over-HTTPS (DoH) and Oblivious DoH (ODoH) encryption
- **Tor** (port 9053) - SOCKS5 proxy for IP anonymization (client-only mode)

## 🚀 Quick Start

### Prerequisites
- Fresh Alpine Linux 3.22+ VPS
- Root access
- Public IPv4 address
- 512MB RAM minimum (1GB recommended)

### Installation

**⚠️ IMPORTANT: This is a TWO-PHASE installation process**

#### Phase 1: Kernel Upgrade

On a fresh Alpine Linux VPS, run as root:

```bash
wget https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/install-dns-privacy-chain.sh
chmod +x install-dns-privacy-chain.sh
sh install-dns-privacy-chain.sh
```

**Or** use this one-liner (if you trust the source):
```bash
wget -qO- https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/install-dns-privacy-chain.sh | sh
```

The script will:
1. Detect if you're running the virt kernel
2. Install linux-lts kernel for full networking support
3. **Exit and ask you to reboot**

**Manually reboot your server:**
```bash
reboot
```

#### Phase 2: Service Installation

After reboot, run the script again:

```bash
sh install-dns-privacy-chain.sh
```

The script will:
1. Detect the LTS kernel is active
2. Install and configure all DNS privacy services
3. Start everything automatically

### Alternative Deployment Methods

#### Using deploy.sh Helper Script

From your local machine:
```bash
# Copy script only
./deploy.sh root@YOUR_SERVER_IP

# Copy and execute immediately
./deploy.sh root@YOUR_SERVER_IP --run
```

#### Manual Copy-Paste Method

If wget/curl aren't available:
```bash
cat > install.sh << 'ENDOFSCRIPT'
[Paste entire script content here]
ENDOFSCRIPT

sh install.sh
```

## 📋 Post-Installation Steps

### 1. Complete AdGuard Home Setup

Open the web interface in your browser:
```
http://YOUR_SERVER_IP:3000
```

**Configuration Settings for Setup Wizard:**
- **Admin Web Interface:** `0.0.0.0:3000` (or custom port)
- **DNS server address:** `0.0.0.0`
- **DNS server port:** `53`
- **Upstream DNS servers:** `127.0.0.1:5353` ← **CRITICAL: This connects to Unbound**
- Create your admin username and password

### 2. Verify Installation

Check all services are running:
```bash
rc-status -a | grep -E '(tor|dnscrypt|unbound|AdGuard)'
```

Test each layer of the DNS chain:
```bash
# Layer 1: dnscrypt-proxy via Tor
dig @127.0.0.1 -p 5053 +short example.com

# Layer 2: Unbound with DNSSEC
dig @127.0.0.1 -p 5353 +short example.com

# Layer 3: AdGuard Home (after web setup)
dig @127.0.0.1 +short example.com
```

Verify Tor is active (should show many connections):
```bash
ss -tn | grep 9053
```

Test from external machine:
```bash
dig @YOUR_SERVER_IP example.com
```

### 3. Configure Client Devices

Update DNS settings on your devices/router to use:
```
Primary DNS: YOUR_SERVER_IP
```

## 🏗️ Architecture & Privacy Layers

### How It Works

Each DNS query passes through 7 privacy-enhancing layers:

1. **AdGuard Home** - Blocks ads, trackers, and malicious domains at DNS level
2. **Unbound** - Validates DNSSEC signatures to prevent DNS tampering/spoofing
3. **dnscrypt-proxy** - Encrypts DNS queries using DNS-over-HTTPS (DoH) or Oblivious DoH
4. **Tor SOCKS Proxy** - Routes encrypted DNS through Tor network (client-only, no relay)
5. **Tor Network** - Anonymizes your IP through 3+ relay nodes
6. **ODoH Relay** - Separates query content from source IP for extra privacy
7. **Upstream Resolver** - Final resolution from privacy-respecting DNS servers

### Performance Optimizations

- **Multi-layer caching** - Unbound and dnscrypt-proxy both cache queries
- **DNSSEC validation** - Cryptographically verify DNS responses
- **TCP enforcement** - Force TCP for Tor compatibility
- **Multi-threaded** - Unbound uses 2 threads for better performance

### Tor Client-Only Mode

Tor is configured with:
```
ClientOnly 1              # Never relay traffic for others
SocksPolicy accept 127.0.0.1
SocksPolicy reject *      # Only localhost can connect
```

Your server will **never** act as a Tor relay or exit node - it's purely a client.

## 📁 Configuration Files

All original configs are backed up with `.orig` extension:

- `/etc/tor/torrc` - Tor client-only SOCKS proxy
- `/etc/dnscrypt-proxy/dnscrypt-proxy.toml` - DoH/ODoH configuration
- `/etc/unbound/unbound.conf` - DNSSEC resolver configuration
- `/tmp/AdGuardHome/AdGuardHome.yaml` - Created by AdGuard setup wizard

## 🛠️ Service Management

### Start/Stop/Restart Services

```bash
rc-service tor start|stop|restart|status
rc-service dnscrypt-proxy start|stop|restart|status
rc-service unbound start|stop|restart|status
rc-service AdGuardHome start|stop|restart|status
```

### View Logs

```bash
# System logs for Tor, dnscrypt, Unbound
tail -f /var/log/messages | grep -E "(tor|dnscrypt|unbound)"

# AdGuard Home logs
tail -f /var/log/AdGuardHome.log
```

### Auto-Start on Boot

All services are configured to start automatically via OpenRC:
```bash
rc-update show default | grep -E "(tor|dnscrypt|unbound|AdGuard)"
```

## 🔧 Troubleshooting

### DNS Not Resolving

Test each layer individually to isolate the issue:

```bash
# Test Layer 1 (dnscrypt-proxy)
dig @127.0.0.1 -p 5053 +short example.com

# Test Layer 2 (Unbound)
dig @127.0.0.1 -p 5353 +short example.com

# Test Layer 3 (AdGuard - requires web setup first)
dig @127.0.0.1 +short example.com
```

### Tor Not Connecting

Check Tor status:
```bash
rc-service tor status
```

Check Tor logs:
```bash
grep tor /var/log/messages | tail -20
```

Verify Tor circuit is established:
```bash
ss -tn | grep 9053 | wc -l
```
Should show many active connections (100+)

### Services Not Starting After Reboot

Verify LTS kernel is active (not virt):
```bash
uname -r
```
Should show: `6.12.53-0-lts` (or similar)

Check service status:
```bash
rc-status -a | grep -E "(tor|dnscrypt|unbound|AdGuard)"
```

### AdGuard Web UI Not Loading

Check if AdGuard is running:
```bash
ss -tulnp | grep :3000
```

Check AdGuard logs:
```bash
tail -50 /var/log/AdGuardHome.log
```

### Line Ending Issues

If you see errors like `line 7: : not found`, the script has Windows line endings:
```bash
# Fix line endings
tr -d '\r' < install-dns-privacy-chain.sh > install.sh
chmod +x install.sh
sh install.sh
```

## 🔐 Security Recommendations

### Essential Security Hardening

1. **Configure a firewall** - The installer does NOT configure iptables. Set up manually:
   ```bash
   # Allow SSH, DNS, HTTP (example - customize for your needs)
   iptables -A INPUT -i lo -j ACCEPT
   iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
   iptables -A INPUT -p tcp --dport 22 -j ACCEPT
   iptables -A INPUT -p tcp --dport 53 -j ACCEPT
   iptables -A INPUT -p udp --dport 53 -j ACCEPT
   iptables -A INPUT -p tcp --dport 3000 -j ACCEPT
   iptables -P INPUT DROP
   ```

2. **Use SSH key authentication** - Disable password authentication
   ```bash
   # /etc/ssh/sshd_config
   PasswordAuthentication no
   ```

3. **Change default SSH port** - Reduces automated attacks
   ```bash
   # /etc/ssh/sshd_config
   Port 2222  # or your choice
   ```

4. **Enable HTTPS for AdGuard** - Protect web interface with TLS

5. **Regular updates**
   ```bash
   apk update && apk upgrade
   ```

6. **Monitor logs** - Watch for suspicious activity
   ```bash
   tail -f /var/log/messages
   ```

### DNS Privacy Best Practices

- Use AdGuard's blocklists to prevent tracking
- Enable query logging only when troubleshooting
- Rotate logs regularly to save disk space
- Consider rate limiting to prevent abuse

## 📊 System Requirements

- **OS:** Alpine Linux 3.22+ (tested on 3.22.2)
- **Kernel:** linux-lts (automatically installed)
- **RAM:** 512MB minimum, 1GB recommended
- **Disk:** 2GB minimum (mostly for linux-firmware)
- **CPU:** Any (tested on x86_64 and aarch64)
- **Network:** Public IPv4 address, outbound HTTPS/Tor access

## 🗑️ Uninstallation

To completely remove all components:

```bash
# Stop all services
rc-service AdGuardHome stop
rc-service unbound stop
rc-service dnscrypt-proxy stop
rc-service tor stop

# Disable auto-start
rc-update del AdGuardHome
rc-update del unbound default
rc-update del dnscrypt-proxy default
rc-update del tor default

# Remove packages
apk del tor dnscrypt-proxy unbound bind-tools

# Remove AdGuard Home
/tmp/AdGuardHome/AdGuardHome -s uninstall
rm -rf /tmp/AdGuardHome

# Remove config files
rm -f /etc/tor/torrc
rm -f /etc/dnscrypt-proxy/dnscrypt-proxy.toml
rm -f /etc/unbound/unbound.conf
```

## ❓ FAQ

**Q: Why two phases? Can't this be done in one run?**
A: Alpine's virt kernel lacks full netfilter support. We must install linux-lts and reboot before services can function properly.

**Q: Will my Tor node relay traffic for others?**
A: No. Tor is configured with `ClientOnly 1` - it will never act as a relay or exit node.

**Q: Does this work on other distributions?**
A: No, this script is Alpine Linux specific (uses apk, OpenRC). Could be adapted for other distros.

**Q: Why isn't iptables/firewall configured?**
A: During testing, automated firewall configuration caused SSH lockouts on reboot. Configure manually for your specific needs.

**Q: Can I run this on an existing system?**
A: Not recommended. This script is designed for fresh VPS installations to avoid conflicts.

**Q: What DNS resolvers does dnscrypt-proxy use?**
A: It uses public resolver lists that support DoH/ODoH and have no-logging policies. See dnscrypt-proxy.toml for details.

## 📜 License

This script is provided as-is for educational and privacy purposes.

## 🙏 Credits

Based on the Wiregate DNS privacy architecture. Adapted for standalone Alpine Linux VPS deployment.

## 📞 Support

For issues or questions:
- Check logs: `/var/log/messages` and `/var/log/AdGuardHome.log`
- Verify service status: `rc-status -a`
- Test each DNS layer individually (see Troubleshooting)
- Open an issue on GitHub

---

**⚠️ Privacy Notice:** While this setup significantly enhances DNS privacy, no solution is 100% perfect. Use in combination with other privacy tools (VPN, browser extensions, etc.) for comprehensive protection.
