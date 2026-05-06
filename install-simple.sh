#!/bin/bash
# AI-Xray Professional Mode Installer (Simplified)
# https://github.com/ScientificInternet/AI-Xray
# MIT License

set -e

# ==================== Colors ====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

# ==================== Config ====================
INSTALL_DIR="/etc/ai-xray"
CONFIG_FILE="${INSTALL_DIR}/config.json"
REALITY_KEY="${INSTALL_DIR}/reality.key"

# dest pool by region
DEST_POOL_US='["addons.mozilla.org","www.cisco.com","www.apple.com","www.microsoft.com","www.cloudflare.com"]'
DEST_POOL_EU='["addons.mozilla.org","www.cisco.com","www.samsung.com","www.apple.com","www.oracle.com"]'
DEST_POOL_AP='["www.samsung.com","www.apple.com","addons.mozilla.org","www.cisco.com","www.asus.com"]'

# whitelist domains
WHITELIST_DOMAINS='["business.tiktok.com","ads.tiktok.com","seller.tiktok.com","sellercentral.amazon.com","advertising.amazon.com","ads.google.com","merchants.google.com","business.facebook.com","www.facebook.com","admin.shopify.com","accounts.shopify.com","api.openai.com","chat.openai.com","claude.ai","gemini.google.com"]'

# ==================== Utilities ====================

info() { echo -e "${CYAN}[AI-Xray]${PLAIN} $1"; }
ok() { echo -e "${GREEN}[AI-Xray]${PLAIN} $1"; }
warn() { echo -e "${YELLOW}[AI-Xray]${PLAIN} $1"; }
fail() { echo -e "${RED}[AI-Xray]${PLAIN} $1"; exit 1; }

check_root() {
  [[ $EUID -ne 0 ]] && fail "Please run as root"
}

# ==================== System Detection ====================

detect_system() {
  info "Detecting system..."

  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    OS_VERSION=$VERSION_ID
  else
    fail "Cannot detect OS. Requires Debian/Ubuntu/CentOS."
  fi

  ARCH=$(uname -m)
  case $ARCH in
    x86_64) ARCH="64" ;;
    aarch64|arm64) ARCH="arm64-v8a" ;;
    *) fail "Unsupported architecture: $ARCH" ;;
  esac

  ok "System: $OS $OS_VERSION ($ARCH)"
}

# ==================== Dependencies ====================

install_deps() {
  info "Installing dependencies..."

  case $OS in
    ubuntu|debian)
      apt-get update -qq
      apt-get install -y curl wget jq unzip sqlite3 >/dev/null 2>&1
      ;;
    centos|rhel|rocky|almalinux)
      yum install -y curl wget jq unzip sqlite >/dev/null 2>&1
      ;;
    *)
      fail "Unsupported OS: $OS"
      ;;
  esac

  ok "Dependencies installed"
}

# ==================== BBR ====================

enable_bbr() {
  info "Enabling BBR..."

  if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr; then
    ok "BBR already enabled"
    return
  fi

  echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
  echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
  sysctl -p >/dev/null 2>&1

  if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr; then
    ok "BBR enabled"
  else
    warn "BBR may not be supported by your kernel"
  fi
}

# ==================== Xray Installation ====================

install_xray() {
  info "Installing Xray-core..."

  if command -v xray >/dev/null 2>&1; then
    warn "Xray already installed, skipping..."
    return
  fi

  bash <(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh) install >/dev/null 2>&1

  if ! command -v xray >/dev/null 2>&1; then
    fail "Xray installation failed"
  fi

  local ver=$(xray version 2>/dev/null | head -1 | awk '{print $2}')
  ok "Xray $ver installed"
}

# ==================== Generate Keys ====================

generate_keys() {
  info "Generating Reality keys..."

  local keys=$(xray x25519)
  PRIVATE_KEY=$(echo "$keys" | grep "Private" | awk '{print $NF}')
  PUBLIC_KEY=$(echo "$keys" | grep "Public" | awk '{print $NF}')

  UUID=$(xray uuid)
  SHORT_ID=$(openssl rand -hex 8)

  # Detect region and select dest pool (with fallback)
  local country=$(curl -s --max-time 3 https://ipapi.co/country_code/ 2>/dev/null || \
                  curl -s --max-time 3 https://ifconfig.co/country-iso 2>/dev/null || \
                  echo "US")
  case $country in
    CN|HK|TW|SG|JP|KR) DEST_POOL=$DEST_POOL_AP ;;
    GB|DE|FR|NL|IT|ES) DEST_POOL=$DEST_POOL_EU ;;
    *) DEST_POOL=$DEST_POOL_US ;;
  esac

  DEST=$(echo "$DEST_POOL" | jq -r '.[0]')

  # Save reality keys
  cat > "${REALITY_KEY}" << KEYEOF
private: ${PRIVATE_KEY}
public: ${PUBLIC_KEY}
KEYEOF

  ok "Keys generated (dest: $DEST)"
}

# ==================== Write Config ====================

write_config() {
  info "Writing Xray configuration..."

  mkdir -p "$INSTALL_DIR"

  cat > "$CONFIG_FILE" << EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "reality-in",
      "listen": "0.0.0.0",
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${DEST}:443",
          "xver": 0,
          "serverNames": ["${DEST}"],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": ["", "${SHORT_ID}"]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom"
    },
    {
      "tag": "block",
      "protocol": "blackhole"
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "domain": $(echo "$WHITELIST_DOMAINS" | jq -c '.'),
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "block"
      }
    ]
  }
}
EOF

  ok "Configuration written"
}

# ==================== Start Services ====================

start_services() {
  info "Starting Xray..."

  systemctl enable xray >/dev/null 2>&1
  systemctl restart xray

  sleep 2
  if systemctl is-active xray >/dev/null 2>&1; then
    ok "Xray running"
  else
    fail "Xray failed to start. Check: journalctl -u xray"
  fi
}

# ==================== Show Result ====================

show_result() {
  local server_ip=$(curl -s --max-time 3 https://api.ipify.org 2>/dev/null || \
                    curl -s --max-time 3 https://ifconfig.me 2>/dev/null || \
                    curl -s --max-time 3 https://icanhazip.com 2>/dev/null || \
                    ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d/ -f1 | head -1)

  echo ""
  echo -e "${GREEN}========================================${PLAIN}"
  echo -e "${GREEN}  AI-Xray Installation Complete${PLAIN}"
  echo -e "${GREEN}========================================${PLAIN}"
  echo ""
  echo -e "${CYAN}Server:${PLAIN} $server_ip:443"
  echo -e "${CYAN}UUID:${PLAIN} $UUID"
  echo -e "${CYAN}Public Key:${PLAIN} $PUBLIC_KEY"
  echo -e "${CYAN}Short ID:${PLAIN} $SHORT_ID"
  echo -e "${CYAN}SNI:${PLAIN} $DEST"
  echo ""
  echo -e "${CYAN}VLESS Link:${PLAIN}"
  echo "vless://${UUID}@${server_ip}:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${DEST}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none#AI-Xray"
  echo ""
  echo -e "${YELLOW}Note:${PLAIN} Default whitelist only allows cross-border e-commerce platforms."
  echo -e "${YELLOW}Edit whitelist:${PLAIN} nano ${CONFIG_FILE}"
  echo ""
}

# ==================== Main ====================

main() {
  check_root
  detect_system
  install_deps
  enable_bbr
  install_xray
  generate_keys
  write_config
  start_services
  show_result
}

main "$@"
