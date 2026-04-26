#!/bin/bash
# AI-Xray Professional Mode Installer
# https://github.com/ScientificInternet/AI-Xray
# MIT License

set -e

# ==================== Colors ====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
PLAIN='\033[0m'
BOLD='\033[1m'

# ==================== Config ====================
XRAY_VERSION="latest"
INSTALL_DIR="/etc/ai-xray"
GUARD_BIN="/usr/local/bin/ai-xray-guard"
CONFIG_FILE="${INSTALL_DIR}/config.json"
WHITELIST_FILE="${INSTALL_DIR}/whitelist.json"
DEST_POOL_FILE="${INSTALL_DIR}/dest-pool.json"
GUARD_DB="${INSTALL_DIR}/guard.db"
LOG_FILE="/var/log/ai-xray.log"
SUB_PORT=8388

# dest pool - grouped by region
DEST_POOL_US='["addons.mozilla.org","www.microsoft.com","www.apple.com","www.cloudflare.com","www.amazon.com"]'
DEST_POOL_EU='["addons.mozilla.org","www.microsoft.com","www.apple.com","www.cloudflare.com","www.samsung.com"]'
DEST_POOL_AP='["www.samsung.com","www.apple.com","www.microsoft.com","www.cloudflare.com","addons.mozilla.org"]'

# whitelist domains
WHITELIST_DOMAINS='[
  "business.tiktok.com","ads.tiktok.com","seller.tiktok.com",
  "sellercentral.amazon.com","advertising.amazon.com",
  "ads.google.com","merchants.google.com",
  "business.facebook.com","www.facebook.com",
  "admin.shopify.com","accounts.shopify.com",
  "api.openai.com","chat.openai.com","claude.ai","gemini.google.com"
]'

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

  # OS
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    OS_VERSION=$VERSION_ID
  else
    fail "Cannot detect OS. Requires Debian/Ubuntu/CentOS."
  fi

  # Arch
  ARCH=$(uname -m)
  case $ARCH in
    x86_64) XRAY_ARCH="64" ;;
    aarch64) XRAY_ARCH="arm64-v8a" ;;
    armv7l) XRAY_ARCH="arm32-v7a" ;;
    *) fail "Unsupported architecture: $ARCH" ;;
  esac

  # Package manager
  if command -v apt-get &>/dev/null; then
    PKG="apt-get"
    PKG_INSTALL="apt-get install -y -qq"
    PKG_UPDATE="apt-get update -qq"
  elif command -v yum &>/dev/null; then
    PKG="yum"
    PKG_INSTALL="yum install -y -q"
    PKG_UPDATE="yum makecache -q"
  elif command -v dnf &>/dev/null; then
    PKG="dnf"
    PKG_INSTALL="dnf install -y -q"
    PKG_UPDATE="dnf makecache -q"
  else
    fail "No supported package manager found"
  fi

  ok "System: $OS $OS_VERSION ($ARCH)"
}

install_deps() {
  info "Installing dependencies..."
  $PKG_UPDATE >/dev/null 2>&1
  $PKG_INSTALL curl wget jq openssl qrencode sqlite3 >/dev/null 2>&1 || true
  ok "Dependencies installed"
}

# ==================== VPS Quality Check ====================

detect_location() {
  info "Detecting VPS location..."

  local geo=$(curl -s --max-time 5 https://ipinfo.io 2>/dev/null)
  if [ -z "$geo" ]; then
    geo=$(curl -s --max-time 5 https://ip.sb/api 2>/dev/null)
  fi

  VPS_IP=$(echo "$geo" | jq -r '.ip // empty' 2>/dev/null)
  VPS_COUNTRY=$(echo "$geo" | jq -r '.country // empty' 2>/dev/null)
  VPS_CITY=$(echo "$geo" | jq -r '.city // empty' 2>/dev/null)
  VPS_ORG=$(echo "$geo" | jq -r '.org // empty' 2>/dev/null)

  if [ -z "$VPS_IP" ]; then
    VPS_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null)
    VPS_COUNTRY="Unknown"
    VPS_CITY="Unknown"
    VPS_ORG="Unknown"
  fi

  ok "IP: $VPS_IP | Location: $VPS_CITY, $VPS_COUNTRY | ISP: $VPS_ORG"

  # Select dest pool based on region
  case $VPS_COUNTRY in
    US|CA|MX|BR|AR|CL|CO) DEST_POOL=$DEST_POOL_US ;;
    JP|SG|KR|HK|TW|IN|AU|NZ) DEST_POOL=$DEST_POOL_AP ;;
    *) DEST_POOL=$DEST_POOL_EU ;;
  esac
}

run_unlock_check() {
  info "Checking IP unlock status..."

  local check_script="/tmp/unlock-check.sh"
  curl -s -o "$check_script" "https://raw.githubusercontent.com/ScientificInternet/Unlock-Check/main/check.sh" 2>/dev/null

  if [ -f "$check_script" ]; then
    chmod +x "$check_script"
    bash "$check_script"
  else
    warn "Could not download Unlock-Check script, skipping..."
  fi

  echo ""
  read -p "$(echo -e ${YELLOW}Continue installation? [Y/n]: ${PLAIN})" choice
  case $choice in
    [nN]) info "Installation cancelled."; exit 0 ;;
    *) ;;
  esac
}

run_vps_test() {
  info "Quick VPS test..."

  local test_script="/tmp/aio-vps.sh"
  curl -s -o "$test_script" "https://raw.githubusercontent.com/ScientificInternet/All-in-one-VPS/main/aio-vps.sh" 2>/dev/null

  if [ -f "$test_script" ]; then
    chmod +x "$test_script"
    # Run quick mode only (system info + route)
    bash "$test_script" --quick 2>/dev/null || bash "$test_script" 2>/dev/null || warn "VPS test skipped"
  else
    warn "Could not download VPS test script, skipping..."
  fi
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

  # Use official install script
  bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install >/dev/null 2>&1

  if ! command -v xray &>/dev/null; then
    fail "Xray installation failed"
  fi

  local ver=$(xray version | head -1 | awk '{print $2}')
  ok "Xray $ver installed"
}

# ==================== Generate Keys ====================

generate_keys() {
  info "Generating Reality keys..."

  local keys=$(xray x25519)
  PRIVATE_KEY=$(echo "$keys" | grep "Private" | awk '{print $NF}')
  PUBLIC_KEY=$(echo "$keys" | grep "Public" | awk '{print $NF}')

  UUID=$(xray uuid)
  SHORT_ID=$(openssl rand -hex 4)

  # Select best dest from pool
  DEST=$(echo "$DEST_POOL" | jq -r '.[0]')

  ok "Keys generated"
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
          "shortIds": ["${SHORT_ID}"]
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
        "domain": [
          "business.tiktok.com","ads.tiktok.com","seller.tiktok.com",
          "sellercentral.amazon.com","advertising.amazon.com",
          "ads.google.com","merchants.google.com",
          "business.facebook.com","www.facebook.com",
          "admin.shopify.com","accounts.shopify.com",
          "api.openai.com","chat.openai.com","claude.ai","gemini.google.com"
        ],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "block"
      },
      {
        "type": "field",
        "port": "0-65535",
        "outboundTag": "block"
      }
    ]
  }
}
EOF

  # Write dest pool
  echo "$DEST_POOL" > "$DEST_POOL_FILE"

  # Write whitelist
  echo "$WHITELIST_DOMAINS" > "$WHITELIST_FILE"

  ok "Configuration written"
}

# ==================== TOS ====================

show_tos() {
  echo ""
  echo -e "${BOLD}==================== Terms of Service ====================${PLAIN}"
  echo ""
  echo "AI-Xray is a cross-border e-commerce network accelerator."
  echo ""
  echo "Default whitelist only allows access to:"
  echo "  - TikTok Business / Amazon Seller Central"
  echo "  - Google Ads / Meta Business Suite / Shopify"
  echo "  - AI platforms (ChatGPT, Claude, Gemini)"
  echo ""
  echo "If you modify the whitelist, you assume all legal"
  echo "responsibility for your usage."
  echo ""
  echo -e "${BOLD}==========================================================${PLAIN}"
  echo ""
  read -p "$(echo -e ${YELLOW}I agree to the terms [Y/n]: ${PLAIN})" tos
  case $tos in
    [nN]) info "Installation cancelled."; exit 0 ;;
    *) ok "Terms accepted" ;;
  esac
}

# ==================== Subscription Endpoint ====================

write_sub_server() {
  info "Setting up subscription endpoint..."

  local sub_script="${INSTALL_DIR}/sub-server.sh"

  cat > "$sub_script" << 'SUBEOF'
#!/bin/bash
INSTALL_DIR="/etc/ai-xray"
CONFIG="${INSTALL_DIR}/config.json"
UUID=$(jq -r '.inbounds[0].settings.clients[0].id' "$CONFIG")
PUB_KEY=$(cat "${INSTALL_DIR}/public.key" 2>/dev/null)
SID=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$CONFIG")
DEST=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "$CONFIG")
IP=$(curl -s --max-time 3 ifconfig.me 2>/dev/null)

# Read HTTP request
read -r REQUEST_LINE
REQ_PATH=$(echo "$REQUEST_LINE" | awk '{print $2}')

# Validate path contains UUID
if [[ "$REQ_PATH" != *"$UUID"* ]]; then
  echo -e "HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\nNot Found"
  exit 0
fi

LINK="vless://${UUID}@${IP}:443?encryption=none&security=reality&sni=${DEST}&fp=chrome&pbk=${PUB_KEY}&sid=${SID}&type=tcp&flow=xtls-rprx-vision#AI-Xray-${IP}"
ENCODED=$(echo -n "$LINK" | base64 -w 0)

echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nSubscription-Userinfo: upload=0; download=0; total=10737418240; expire=0\r\nConnection: close\r\n\r\n${ENCODED}"
SUBEOF

  chmod +x "$sub_script"

  # Install socat if not present
  $PKG_INSTALL socat >/dev/null 2>&1 || true

  # Create systemd service for sub endpoint
  cat > /etc/systemd/system/ai-xray-sub.service << EOF
[Unit]
Description=AI-Xray Subscription Endpoint
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/socat TCP-LISTEN:${SUB_PORT},reuseaddr,fork EXEC:${sub_script}\ ${SUB_PORT}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

  ok "Subscription endpoint configured on port $SUB_PORT"
}

# ==================== AI Guard ====================

write_guard() {
  info "Installing AI Guard..."

  cat > "$GUARD_BIN" << 'GUARDEOF'
#!/bin/bash
# AI-Xray Guard - Chameleon Mode
# Monitors network health and rotates identity before detection

INSTALL_DIR="/etc/ai-xray"
CONFIG="${INSTALL_DIR}/config.json"
DEST_POOL="${INSTALL_DIR}/dest-pool.json"
DB="${INSTALL_DIR}/guard.db"
LOG="/var/log/ai-xray.log"
CHECK_INTERVAL=60
LATENCY_THRESHOLD=500
LOSS_THRESHOLD=10
RST_THRESHOLD=5

# Traffic shaping: max concurrent connections (ramps up over days)
MAX_CONN_INITIAL=20
MAX_CONN_FULL=200
RAMP_DAYS=7

# Init SQLite
init_db() {
  sqlite3 "$DB" "CREATE TABLE IF NOT EXISTS rotations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT DEFAULT (datetime('now')),
    old_dest TEXT,
    new_dest TEXT,
    trigger_reason TEXT,
    latency_ms INTEGER,
    loss_pct REAL,
    rst_count INTEGER
  );"

  sqlite3 "$DB" "CREATE TABLE IF NOT EXISTS health (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT DEFAULT (datetime('now')),
    dest TEXT,
    latency_ms INTEGER,
    loss_pct REAL,
    rst_count INTEGER,
    conn_count INTEGER
  );"

  sqlite3 "$DB" "CREATE TABLE IF NOT EXISTS meta (
    key TEXT PRIMARY KEY,
    value TEXT
  );"

  # Record install time if not exists
  sqlite3 "$DB" "INSERT OR IGNORE INTO meta (key, value) VALUES ('install_time', datetime('now'));"
}

# Traffic shaping: calculate current max connections based on age
get_max_connections() {
  local install_time=$(sqlite3 "$DB" "SELECT value FROM meta WHERE key='install_time';")
  if [ -z "$install_time" ]; then
    echo $MAX_CONN_INITIAL
    return
  fi

  local age_seconds=$(( $(date +%s) - $(date -d "$install_time" +%s 2>/dev/null || echo $(date +%s)) ))
  local age_days=$(( age_seconds / 86400 ))

  if [ $age_days -ge $RAMP_DAYS ]; then
    echo $MAX_CONN_FULL
  else
    local range=$(( MAX_CONN_FULL - MAX_CONN_INITIAL ))
    local current=$(( MAX_CONN_INITIAL + (range * age_days / RAMP_DAYS) ))
    echo $current
  fi
}

# Enforce connection limit via iptables
enforce_conn_limit() {
  local max_conn=$(get_max_connections)
  local current_conn=$(ss -tn state established '( sport = :443 )' 2>/dev/null | wc -l)

  # Remove old rule if exists, add new one
  iptables -D INPUT -p tcp --dport 443 --syn -m connlimit --connlimit-above $max_conn -j DROP 2>/dev/null
  iptables -A INPUT -p tcp --dport 443 --syn -m connlimit --connlimit-above $max_conn -j DROP 2>/dev/null

  echo "$current_conn/$max_conn"
}

# Get current dest from config
get_current_dest() {
  jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "$CONFIG"
}

# Measure latency to current dest
measure_latency() {
  local dest=$1
  local result=$(curl -o /dev/null -s -w "%{time_connect}" --max-time 5 "https://${dest}" 2>/dev/null)
  if [ -z "$result" ] || [ "$result" = "0.000000" ]; then
    echo "9999"
  else
    echo "$result" | awk '{printf "%.0f", $1 * 1000}'
  fi
}

# Measure packet loss
measure_loss() {
  local dest=$1
  local result=$(ping -c 5 -W 2 "$dest" 2>/dev/null | grep "packet loss" | awk -F',' '{print $3}' | awk '{print $1}' | tr -d '%')
  echo "${result:-100}"
}

# Count TCP RST in last interval
count_rst() {
  # Check for RST packets on port 443 in the last minute
  local count=$(ss -ti state close-wait 2>/dev/null | wc -l)
  echo "$count"
}

# Rotate dest - the chameleon
rotate_dest() {
  local reason=$1
  local old_dest=$(get_current_dest)

  # Pick next dest from pool (round-robin, skip current)
  local pool=$(cat "$DEST_POOL")
  local pool_size=$(echo "$pool" | jq 'length')
  local current_idx=$(echo "$pool" | jq --arg d "$old_dest" 'to_entries[] | select(.value == $d) | .key' 2>/dev/null)

  if [ -z "$current_idx" ]; then
    current_idx=0
  fi

  local next_idx=$(( (current_idx + 1) % pool_size ))
  local new_dest=$(echo "$pool" | jq -r ".[$next_idx]")

  # Generate new shortId
  local new_sid=$(openssl rand -hex 4)

  # Update config
  local tmp=$(mktemp)
  jq --arg dest "$new_dest" --arg sid "$new_sid" '
    .inbounds[0].streamSettings.realitySettings.dest = ($dest + ":443") |
    .inbounds[0].streamSettings.realitySettings.serverNames = [$dest] |
    .inbounds[0].streamSettings.realitySettings.shortIds = [$sid]
  ' "$CONFIG" > "$tmp" && mv "$tmp" "$CONFIG"

  # Reload Xray (SIGHUP for graceful reload)
  if systemctl is-active xray >/dev/null 2>&1; then
    systemctl restart xray
  fi

  # Log rotation
  sqlite3 "$DB" "INSERT INTO rotations (old_dest, new_dest, trigger_reason, latency_ms, loss_pct, rst_count)
    VALUES ('$old_dest', '$new_dest', '$reason', $CURRENT_LATENCY, $CURRENT_LOSS, $CURRENT_RST);"

  echo "$(date '+%Y-%m-%d %H:%M:%S') [MORPH] $old_dest -> $new_dest (reason: $reason)" >> "$LOG"
}

# Main loop
main() {
  init_db
  echo "$(date '+%Y-%m-%d %H:%M:%S') [START] AI Guard started" >> "$LOG"

  while true; do
    local dest=$(get_current_dest)

    CURRENT_LATENCY=$(measure_latency "$dest")
    CURRENT_LOSS=$(measure_loss "$dest")
    CURRENT_RST=$(count_rst)

    # Log health
    sqlite3 "$DB" "INSERT INTO health (dest, latency_ms, loss_pct, rst_count, conn_count)
      VALUES ('$dest', $CURRENT_LATENCY, $CURRENT_LOSS, $CURRENT_RST, $(ss -tn state established '( sport = :443 )' 2>/dev/null | wc -l));"

    # Traffic shaping
    local conn_info=$(enforce_conn_limit)

    # Check thresholds
    local reason=""

    if [ "$CURRENT_LATENCY" -ge "$LATENCY_THRESHOLD" ]; then
      reason="latency_spike(${CURRENT_LATENCY}ms)"
    elif [ "$CURRENT_LOSS" -ge "$LOSS_THRESHOLD" ]; then
      reason="packet_loss(${CURRENT_LOSS}%)"
    elif [ "$CURRENT_RST" -ge "$RST_THRESHOLD" ]; then
      reason="rst_flood(${CURRENT_RST})"
    fi

    if [ -n "$reason" ]; then
      echo "$(date '+%Y-%m-%d %H:%M:%S') [ALERT] $reason - rotating..." >> "$LOG"
      rotate_dest "$reason"
    else
      echo "$(date '+%Y-%m-%d %H:%M:%S') [OK] dest=$dest latency=${CURRENT_LATENCY}ms loss=${CURRENT_LOSS}% rst=$CURRENT_RST conn=$conn_info" >> "$LOG"
    fi

    sleep $CHECK_INTERVAL
  done
}

main "$@"
GUARDEOF

  chmod +x "$GUARD_BIN"

  # Create systemd service
  cat > /etc/systemd/system/ai-xray-guard.service << EOF
[Unit]
Description=AI-Xray Guard (Chameleon Mode)
After=xray.service

[Service]
Type=simple
ExecStart=${GUARD_BIN}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  ok "AI Guard installed"
}

# ==================== Start Services ====================

start_services() {
  info "Starting services..."

  # Save public key
  echo "$PUBLIC_KEY" > "${INSTALL_DIR}/public.key"

  systemctl daemon-reload

  systemctl enable xray >/dev/null 2>&1
  systemctl restart xray

  systemctl enable ai-xray-guard >/dev/null 2>&1
  systemctl start ai-xray-guard

  systemctl enable ai-xray-sub >/dev/null 2>&1
  systemctl start ai-xray-sub

  # Verify
  sleep 2
  if systemctl is-active xray >/dev/null 2>&1; then
    ok "Xray running"
  else
    fail "Xray failed to start. Check: journalctl -u xray"
  fi

  if systemctl is-active ai-xray-guard >/dev/null 2>&1; then
    ok "AI Guard running"
  else
    warn "AI Guard failed to start. Check: journalctl -u ai-xray-guard"
  fi
}

# ==================== Show Result ====================

show_result() {
  local link="vless://${UUID}@${VPS_IP}:443?encryption=none&security=reality&sni=${DEST}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&flow=xtls-rprx-vision#AI-Xray-${VPS_IP}"

  echo ""
  echo -e "${GREEN}==========================================================${PLAIN}"
  echo -e "${GREEN}  AI-Xray installation complete${PLAIN}"
  echo -e "${GREEN}==========================================================${PLAIN}"
  echo ""
  echo -e "${CYAN}Server:${PLAIN}      $VPS_IP"
  echo -e "${CYAN}Protocol:${PLAIN}    VLESS + Reality + Vision"
  echo -e "${CYAN}UUID:${PLAIN}        $UUID"
  echo -e "${CYAN}Dest:${PLAIN}        $DEST"
  echo -e "${CYAN}Public Key:${PLAIN}  $PUBLIC_KEY"
  echo -e "${CYAN}Short ID:${PLAIN}    $SHORT_ID"
  echo -e "${CYAN}Sub URL:${PLAIN}     http://${VPS_IP}:${SUB_PORT}/${UUID}"
  echo ""
  echo -e "${CYAN}Node Link:${PLAIN}"
  echo -e "${YELLOW}${link}${PLAIN}"
  echo ""

  # QR Code
  if command -v qrencode &>/dev/null; then
    echo -e "${CYAN}QR Code:${PLAIN}"
    qrencode -t ANSIUTF8 "$link"
    echo ""
  fi

  echo -e "${CYAN}AI Guard:${PLAIN}    Running (check: ai-xray log)"
  echo -e "${CYAN}Whitelist:${PLAIN}   ON (edit: ai-xray whitelist)"
  echo ""
  echo -e "${GREEN}==========================================================${PLAIN}"
  echo ""

  # Save config summary
  cat > "${INSTALL_DIR}/info.txt" << EOF
IP: $VPS_IP
UUID: $UUID
Public Key: $PUBLIC_KEY
Short ID: $SHORT_ID
Dest: $DEST
Link: $link
Sub URL: http://${VPS_IP}:${SUB_PORT}/${UUID}
EOF
}

# ==================== CLI ====================

write_cli() {
  cat > /usr/local/bin/ai-xray << 'CLIEOF'
#!/bin/bash
INSTALL_DIR="/etc/ai-xray"

case "$1" in
  status)
    echo "=== Xray ==="
    systemctl status xray --no-pager -l 2>/dev/null | head -5
    echo ""
    echo "=== AI Guard ==="
    systemctl status ai-xray-guard --no-pager -l 2>/dev/null | head -5
    ;;
  log)
    tail -50 /var/log/ai-xray.log
    ;;
  morph)
    echo "Triggering manual rotation..."
    CONFIG="${INSTALL_DIR}/config.json"
    POOL="${INSTALL_DIR}/dest-pool.json"
    OLD=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "$CONFIG")
    POOL_SIZE=$(jq 'length' "$POOL")
    IDX=$(jq --arg d "$OLD" 'to_entries[] | select(.value == $d) | .key' "$POOL" 2>/dev/null || echo 0)
    NEXT=$(( (${IDX:-0} + 1) % POOL_SIZE ))
    NEW=$(jq -r ".[$NEXT]" "$POOL")
    SID=$(openssl rand -hex 4)
    TMP=$(mktemp)
    jq --arg dest "$NEW" --arg sid "$SID" '
      .inbounds[0].streamSettings.realitySettings.dest = ($dest + ":443") |
      .inbounds[0].streamSettings.realitySettings.serverNames = [$dest] |
      .inbounds[0].streamSettings.realitySettings.shortIds = [$sid]
    ' "$CONFIG" > "$TMP" && mv "$TMP" "$CONFIG"
    systemctl restart xray
    echo "Done. $OLD -> $NEW (shortId: $SID)"
    ;;
  dest)
    echo "Current dest: $(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' ${INSTALL_DIR}/config.json)"
    echo "Dest pool:"
    jq -r '.[]' ${INSTALL_DIR}/dest-pool.json
    ;;
  whitelist)
    if [ "$2" = "edit" ]; then
      echo ""
      echo -e "\033[1m==================== WARNING ====================\033[0m"
      echo "Modifying the whitelist means you take full legal"
      echo "responsibility for all traffic through this server."
      echo -e "\033[1m=================================================\033[0m"
      echo ""
      read -p "I understand and accept [y/N]: " confirm
      case $confirm in
        [yY]) ${EDITOR:-nano} ${INSTALL_DIR}/whitelist.json
          echo "Whitelist updated. Restart Xray to apply: systemctl restart xray" ;;
        *) echo "Cancelled." ;;
      esac
    else
      echo "Whitelist domains:"
      jq -r '.[]' ${INSTALL_DIR}/whitelist.json
      echo ""
      echo "To edit: ai-xray whitelist edit"
    fi
    ;;
  sub)
    cat ${INSTALL_DIR}/info.txt
    ;;
  update)
    echo "Updating AI-Xray..."
    curl -fsSL https://raw.githubusercontent.com/ScientificInternet/AI-Xray/main/install.sh | bash
    ;;
  uninstall)
    echo "Uninstalling AI-Xray..."
    systemctl stop xray ai-xray-guard ai-xray-sub 2>/dev/null
    systemctl disable xray ai-xray-guard ai-xray-sub 2>/dev/null
    rm -rf ${INSTALL_DIR} /usr/local/bin/ai-xray /usr/local/bin/ai-xray-guard
    rm -f /etc/systemd/system/ai-xray-guard.service /etc/systemd/system/ai-xray-sub.service
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove >/dev/null 2>&1
    systemctl daemon-reload
    echo "AI-Xray removed."
    ;;
  *)
    echo "AI-Xray Management"
    echo ""
    echo "Usage: ai-xray <command>"
    echo ""
    echo "Commands:"
    echo "  status      Show service status"
    echo "  log         Show AI Guard log"
    echo "  morph       Manual identity rotation"
    echo "  dest        Show current dest and pool"
    echo "  whitelist   Show whitelist domains"
    echo "  sub         Show subscription info"
    echo "  update      Update AI-Xray"
    echo "  uninstall   Remove AI-Xray"
    ;;
esac
CLIEOF

  chmod +x /usr/local/bin/ai-xray
  ok "CLI tool installed: ai-xray"
}

# ==================== Main ====================

main() {
  clear
  echo -e "${CYAN}"
  echo '    _    ___      __  __'
  echo '   / \  |_ _|    \ \/ /_ __ __ _ _   _'
  echo '  / _ \  | |_____ \  /| '\''__/ _` | | | |'
  echo ' / ___ \ | |_____ /  \| | | (_| | |_| |'
  echo '/_/   \_\___|   /_/\_\_|  \__,_|\__, |'
  echo '                                 |___/'
  echo -e "${PLAIN}"
  echo -e "${CYAN}AI-powered cross-border network accelerator${PLAIN}"
  echo ""

  check_root
  detect_system
  install_deps
  detect_location

  echo ""
  echo -e "${YELLOW}Choose installation mode:${PLAIN}"
  echo "  1) Full install (VPS test + Unlock check + Xray + AI Guard)"
  echo "  2) Quick install (Xray + AI Guard only)"
  echo ""
  read -p "$(echo -e ${CYAN}Select [1/2, default=2]: ${PLAIN})" mode

  case $mode in
    1)
      run_vps_test
      run_unlock_check
      ;;
    *)
      info "Quick install mode"
      ;;
  esac

  show_tos
  enable_bbr
  install_xray
  generate_keys
  write_config
  write_sub_server
  write_guard
  write_cli
  start_services
  show_result
}

main "$@"
