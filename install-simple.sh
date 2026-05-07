#!/bin/bash
# AI-Xray Reality Installer
# https://github.com/ScientificInternet/AI-Xray

# 等待1秒避免curl输出冲突
sleep 1

# Colors
red='\e[91m'
green='\e[92m'
yellow='\e[93m'
cyan='\e[96m'
none='\e[0m'

echo -e "${cyan}========================================${none}"
echo -e "${cyan}AI-Xray Reality Installer${none}"
echo -e "${cyan}========================================${none}"

# Check root
if [[ $EUID -ne 0 ]]; then
   echo -e "${red}Error: Please run as root${none}"
   exit 1
fi

# Detect system
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS=$ID
else
    echo -e "${red}Error: Cannot detect OS${none}"
    exit 1
fi

echo -e "${green}Detected: $OS${none}"

# Install dependencies
echo -e "${yellow}Installing dependencies...${none}"
case $OS in
    ubuntu|debian)
        apt-get update -qq
        apt-get install -y curl wget jq unzip sqlite3
        ;;
    centos|rhel|rocky|almalinux)
        yum install -y curl wget unzip sqlite
        ;;
    *)
        echo -e "${red}Unsupported OS: $OS${none}"
        exit 1
        ;;
esac

echo -e "${green}Dependencies installed${none}"

# Install Xray with pinned version and checksum verification
echo -e "${yellow}Installing Xray...${none}"

XRAY_INSTALL_COMMIT="e741a4f5"
XRAY_INSTALL_SHA256="7f70c95f6b418da8b4f4883343d602964915e28748993870fd554383afdbe555"
XRAY_INSTALL_URL="https://raw.githubusercontent.com/XTLS/Xray-install/${XRAY_INSTALL_COMMIT}/install-release.sh"
XRAY_INSTALL_TMP="/tmp/xray-install-$$.sh"

if ! curl -fsSL "$XRAY_INSTALL_URL" -o "$XRAY_INSTALL_TMP"; then
    echo -e "${red}Failed to download Xray installer${none}"
    exit 1
fi

echo "${XRAY_INSTALL_SHA256}  ${XRAY_INSTALL_TMP}" | sha256sum -c - >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
    echo -e "${red}Checksum verification failed${none}"
    rm -f "$XRAY_INSTALL_TMP"
    exit 1
fi

bash "$XRAY_INSTALL_TMP" install
rm -f "$XRAY_INSTALL_TMP"

if ! command -v xray >/dev/null 2>&1; then
    echo -e "${red}Xray installation failed${none}"
    exit 1
fi

xray_version=$(xray version 2>/dev/null | head -1 | awk '{print $2}')
echo -e "${green}Xray $xray_version installed${none}"

# Generate keys
echo -e "${yellow}Generating keys...${none}"
keys=$(xray x25519)
PRIVATE_KEY=$(echo "$keys" | grep "Private" | awk '{print $NF}')
PUBLIC_KEY=$(echo "$keys" | grep "Public" | awk '{print $NF}')
UUID=$(xray uuid)
SHORT_ID=$(openssl rand -hex 8)

echo -e "${green}Keys generated${none}"

# Get server IP
echo -e "${yellow}Detecting server IP...${none}"
SERVER_IP=$(curl -s --max-time 3 https://api.ipify.org || curl -s --max-time 3 https://ifconfig.me || echo "YOUR_SERVER_IP")

# Detect region and select dest
REGION=$(curl -s --max-time 3 https://ifconfig.co/country-iso || echo "US")
case $REGION in
    US|CA|MX)
        DEST="addons.mozilla.org"
        ;;
    GB|DE|FR|NL|IT|ES)
        DEST="www.cisco.com"
        ;;
    *)
        DEST="www.apple.com"
        ;;
esac

echo -e "${green}Region: $REGION, Dest: $DEST${none}"

# Write config
echo -e "${yellow}Writing configuration...${none}"

cat > /usr/local/etc/xray/config.json << EOF
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
            "id": "$UUID",
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
          "dest": "$DEST:443",
          "xver": 0,
          "serverNames": ["$DEST"],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": ["", "$SHORT_ID"]
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
        "domain": ["business.tiktok.com","ads.tiktok.com","seller.tiktok.com","sellercentral.amazon.com","advertising.amazon.com","ads.google.com","merchants.google.com","business.facebook.com","www.facebook.com","admin.shopify.com","accounts.shopify.com","api.openai.com","chat.openai.com","claude.ai","gemini.google.com"],
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

echo -e "${green}Configuration written${none}"

# Enable BBR
echo -e "${yellow}Enabling BBR...${none}"
sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
sysctl -p >/dev/null 2>&1
echo -e "${green}BBR enabled${none}"

# Start service
echo -e "${yellow}Starting Xray service...${none}"
systemctl restart xray
systemctl enable xray >/dev/null 2>&1

if systemctl is-active --quiet xray; then
    echo -e "${green}Xray service started${none}"
else
    echo -e "${red}Xray service failed to start${none}"
    exit 1
fi

# Show result
echo ""
echo -e "${green}========================================${none}"
echo -e "${green}Installation Complete!${none}"
echo -e "${green}========================================${none}"
echo ""
echo -e "${cyan}Server:${none} $SERVER_IP:443"
echo -e "${cyan}UUID:${none} $UUID"
echo -e "${cyan}Public Key:${none} $PUBLIC_KEY"
echo -e "${cyan}Short ID:${none} $SHORT_ID"
echo -e "${cyan}SNI:${none} $DEST"
echo ""
echo -e "${cyan}VLESS Link:${none}"
echo "vless://${UUID}@${SERVER_IP}:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${DEST}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none#AI-Xray"
echo ""
echo -e "${yellow}Note:${none} Default whitelist only allows cross-border e-commerce platforms."
echo -e "${yellow}Edit whitelist:${none} nano /usr/local/etc/xray/config.json"
echo ""
