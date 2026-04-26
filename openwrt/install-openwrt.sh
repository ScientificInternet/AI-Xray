#!/bin/sh
# AI-Xray OpenWrt Plugin
# Turns your router into an AI-powered smart proxy
# https://github.com/ScientificInternet/AI-Xray
# MIT License

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

INSTALL_DIR="/etc/ai-xray"
MIHOMO_BIN="/usr/bin/mihomo"
MIHOMO_CONFIG="${INSTALL_DIR}/config.yaml"
AI_DAEMON="${INSTALL_DIR}/ai-router.sh"
API="http://127.0.0.1:9090"
API_SECRET=""
LOG_FILE="/var/log/ai-xray-router.log"
CHECK_INTERVAL=30
WEIGHTS_URL="https://github.com/ScientificInternet/AI-Xray/releases/latest/download/model-weights.json"

info() { echo -e "${CYAN}[AI-Xray]${PLAIN} $1"; }
ok() { echo -e "${GREEN}[AI-Xray]${PLAIN} $1"; }
warn() { echo -e "${YELLOW}[AI-Xray]${PLAIN} $1"; }
fail() { echo -e "${RED}[AI-Xray]${PLAIN} $1"; exit 1; }

# ==================== Detect OpenWrt ====================

detect_arch() {
  ARCH=$(uname -m)
  case $ARCH in
    x86_64) MIHOMO_ARCH="linux-amd64" ;;
    aarch64) MIHOMO_ARCH="linux-arm64" ;;
    armv7l) MIHOMO_ARCH="linux-armv7" ;;
    mips*) MIHOMO_ARCH="linux-mipsle-softfloat" ;;
    *) fail "Unsupported architecture: $ARCH" ;;
  esac
  ok "Architecture: $ARCH -> $MIHOMO_ARCH"
}

# ==================== Install mihomo ====================

install_mihomo() {
  if [ -f "$MIHOMO_BIN" ]; then
    local ver=$($MIHOMO_BIN -v 2>/dev/null | head -1)
    ok "mihomo already installed: $ver"
    return
  fi

  info "Downloading mihomo..."

  local release_url="https://github.com/MetaCubeX/mihomo/releases/latest/download/mihomo-${MIHOMO_ARCH}-v1.19.0.gz"
  local tmp="/tmp/mihomo.gz"

  # Try latest release
  curl -sL -o "$tmp" "https://github.com/MetaCubeX/mihomo/releases/latest/download/mihomo-${MIHOMO_ARCH}.gz" 2>/dev/null \
    || wget -q -O "$tmp" "https://github.com/MetaCubeX/mihomo/releases/latest/download/mihomo-${MIHOMO_ARCH}.gz" 2>/dev/null

  if [ ! -f "$tmp" ] || [ ! -s "$tmp" ]; then
    fail "Failed to download mihomo"
  fi

  gzip -d -f "$tmp"
  mv /tmp/mihomo "$MIHOMO_BIN"
  chmod +x "$MIHOMO_BIN"

  ok "mihomo installed: $($MIHOMO_BIN -v 2>/dev/null | head -1)"
}

# ==================== Parse Subscription ====================

parse_subscription() {
  local sub_url="$1"
  info "Fetching subscription: $sub_url"

  local raw=$(curl -s --max-time 15 "$sub_url" 2>/dev/null)
  if [ -z "$raw" ]; then
    fail "Could not fetch subscription"
  fi

  # Try base64 decode
  local decoded=$(echo "$raw" | base64 -d 2>/dev/null)
  if [ -z "$decoded" ]; then
    decoded="$raw"
  fi

  # Parse each line as a node link
  NODES=""
  NODE_COUNT=0

  echo "$decoded" | while IFS= read -r line; do
    line=$(echo "$line" | tr -d '\r')
    [ -z "$line" ] && continue

    case "$line" in
      vless://*|vmess://*|ss://*|trojan://*)
        echo "$line" >> "${INSTALL_DIR}/nodes.txt"
        NODE_COUNT=$((NODE_COUNT + 1))
        ;;
    esac
  done

  NODE_COUNT=$(wc -l < "${INSTALL_DIR}/nodes.txt" 2>/dev/null || echo 0)
  ok "Parsed $NODE_COUNT nodes"

  if [ "$NODE_COUNT" -eq 0 ]; then
    fail "No valid nodes found in subscription"
  fi
}

# ==================== Generate Config ====================

generate_config() {
  info "Generating mihomo configuration..."

  API_SECRET=$(head -c 8 /dev/urandom | od -A n -t x1 | tr -d ' \n')

  # Build proxies section from node links
  local proxies=""
  local proxy_names=""
  local idx=0

  while IFS= read -r line; do
    line=$(echo "$line" | tr -d '\r')
    [ -z "$line" ] && continue
    idx=$((idx + 1))

    case "$line" in
      vless://*)
        local parsed=$(parse_vless "$line" "$idx")
        if [ -n "$parsed" ]; then
          proxies="${proxies}${parsed}\n"
          proxy_names="${proxy_names}      - node-${idx}\n"
        fi
        ;;
      vmess://*)
        local parsed=$(parse_vmess "$line" "$idx")
        if [ -n "$parsed" ]; then
          proxies="${proxies}${parsed}\n"
          proxy_names="${proxy_names}      - node-${idx}\n"
        fi
        ;;
      ss://*)
        local parsed=$(parse_ss "$line" "$idx")
        if [ -n "$parsed" ]; then
          proxies="${proxies}${parsed}\n"
          proxy_names="${proxy_names}      - node-${idx}\n"
        fi
        ;;
      trojan://*)
        local parsed=$(parse_trojan "$line" "$idx")
        if [ -n "$parsed" ]; then
          proxies="${proxies}${parsed}\n"
          proxy_names="${proxy_names}      - node-${idx}\n"
        fi
        ;;
    esac
  done < "${INSTALL_DIR}/nodes.txt"

  # Write config
  cat > "$MIHOMO_CONFIG" << CFGEOF
mixed-port: 7890
redir-port: 7891
tproxy-port: 7892
allow-lan: true
mode: rule
log-level: warning
external-controller: 127.0.0.1:9090
secret: "${API_SECRET}"

dns:
  enable: true
  listen: 0.0.0.0:5353
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  nameserver:
    - https://dns.google/dns-query
    - https://cloudflare-dns.com/dns-query
  fallback:
    - https://1.0.0.1/dns-query
    - https://8.8.4.4/dns-query
  fallback-filter:
    geoip: true
    geoip-code: CN

proxies:
$(echo -e "$proxies")

proxy-groups:
  - name: AI-Proxy
    type: url-test
    url: https://www.gstatic.com/generate_204
    interval: 300
    tolerance: 100
    proxies:
$(echo -e "$proxy_names")

  - name: Proxy
    type: select
    proxies:
      - AI-Proxy
      - DIRECT

rules:
  - GEOSITE,category-ads-all,REJECT
  - GEOSITE,cn,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,Proxy
CFGEOF

  # Save API secret
  echo "$API_SECRET" > "${INSTALL_DIR}/api-secret"

  ok "Configuration generated with $(echo -e "$proxy_names" | grep -c 'node-') nodes"
}

# ==================== Node Parsers ====================

parse_vless() {
  local url="$1"
  local idx="$2"

  # vless://uuid@server:port?params#name
  local uuid=$(echo "$url" | sed 's|vless://||' | cut -d'@' -f1)
  local server_port=$(echo "$url" | sed 's|vless://[^@]*@||' | cut -d'?' -f1)
  local server=$(echo "$server_port" | cut -d':' -f1)
  local port=$(echo "$server_port" | cut -d':' -f2)
  local params=$(echo "$url" | cut -d'?' -f2 | cut -d'#' -f1)

  local security=$(echo "$params" | grep -o 'security=[^&]*' | cut -d'=' -f2)
  local sni=$(echo "$params" | grep -o 'sni=[^&]*' | cut -d'=' -f2)
  local type=$(echo "$params" | grep -o 'type=[^&]*' | cut -d'=' -f2)
  local flow=$(echo "$params" | grep -o 'flow=[^&]*' | cut -d'=' -f2)
  local pbk=$(echo "$params" | grep -o 'pbk=[^&]*' | cut -d'=' -f2)
  local sid=$(echo "$params" | grep -o 'sid=[^&]*' | cut -d'=' -f2)
  local fp=$(echo "$params" | grep -o 'fp=[^&]*' | cut -d'=' -f2)
  local host=$(echo "$params" | grep -o 'host=[^&]*' | cut -d'=' -f2)
  local path=$(echo "$params" | grep -o 'path=[^&]*' | cut -d'=' -f2)

  [ -z "$server" ] || [ -z "$port" ] || [ -z "$uuid" ] && return

  local entry="  - name: node-${idx}
    type: vless
    server: ${server}
    port: ${port}
    uuid: ${uuid}
    network: ${type:-tcp}
    tls: $([ "$security" = "tls" ] || [ "$security" = "reality" ] && echo "true" || echo "false")
    udp: true
    client-fingerprint: ${fp:-chrome}"

  if [ "$security" = "reality" ]; then
    entry="${entry}
    reality-opts:
      public-key: ${pbk}
      short-id: ${sid}
    servername: ${sni}"
  elif [ -n "$sni" ]; then
    entry="${entry}
    sni: ${sni}"
  fi

  if [ -n "$flow" ]; then
    entry="${entry}
    flow: ${flow}"
  fi

  if [ "$type" = "ws" ]; then
    entry="${entry}
    ws-opts:
      path: $(echo "$path" | sed 's/%2F/\//g; s/%3F/?/g; s/%3D/=/g')
      headers:
        Host: ${host:-$server}"
  fi

  echo "$entry"
}

parse_vmess() {
  local url="$1"
  local idx="$2"

  # vmess://base64json
  local json=$(echo "$url" | sed 's|vmess://||' | cut -d'#' -f1 | base64 -d 2>/dev/null)
  [ -z "$json" ] && return

  local server=$(echo "$json" | grep -o '"add":"[^"]*"' | cut -d'"' -f4)
  local port=$(echo "$json" | grep -o '"port":[0-9]*' | cut -d':' -f2)
  [ -z "$port" ] && port=$(echo "$json" | grep -o '"port":"[^"]*"' | cut -d'"' -f4)
  local uuid=$(echo "$json" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
  local aid=$(echo "$json" | grep -o '"aid":[0-9]*' | cut -d':' -f2)
  [ -z "$aid" ] && aid=$(echo "$json" | grep -o '"aid":"[^"]*"' | cut -d'"' -f4)
  local net=$(echo "$json" | grep -o '"net":"[^"]*"' | cut -d'"' -f4)
  local tls=$(echo "$json" | grep -o '"tls":"[^"]*"' | cut -d'"' -f4)
  local host=$(echo "$json" | grep -o '"host":"[^"]*"' | cut -d'"' -f4)
  local path=$(echo "$json" | grep -o '"path":"[^"]*"' | cut -d'"' -f4)

  [ -z "$server" ] || [ -z "$port" ] || [ -z "$uuid" ] && return

  local entry="  - name: node-${idx}
    type: vmess
    server: ${server}
    port: ${port}
    uuid: ${uuid}
    alterId: ${aid:-0}
    cipher: auto
    network: ${net:-tcp}
    tls: $([ "$tls" = "tls" ] && echo "true" || echo "false")
    udp: true"

  if [ "$net" = "ws" ]; then
    entry="${entry}
    ws-opts:
      path: ${path:-/}
      headers:
        Host: ${host:-$server}"
  fi

  echo "$entry"
}

parse_ss() {
  local url="$1"
  local idx="$2"

  # ss://base64(method:password)@server:port#name
  local encoded=$(echo "$url" | sed 's|ss://||' | cut -d'@' -f1 | cut -d'#' -f1)
  local decoded=$(echo "$encoded" | base64 -d 2>/dev/null)
  [ -z "$decoded" ] && return

  local method=$(echo "$decoded" | cut -d':' -f1)
  local password=$(echo "$decoded" | cut -d':' -f2-)

  local server_part=$(echo "$url" | sed 's|ss://[^@]*@||' | cut -d'#' -f1)
  local server=$(echo "$server_part" | cut -d':' -f1)
  local port=$(echo "$server_part" | cut -d':' -f2)

  [ -z "$server" ] || [ -z "$port" ] && return

  echo "  - name: node-${idx}
    type: ss
    server: ${server}
    port: ${port}
    cipher: ${method}
    password: ${password}
    udp: true"
}

parse_trojan() {
  local url="$1"
  local idx="$2"

  # trojan://password@server:port?params#name
  local password=$(echo "$url" | sed 's|trojan://||' | cut -d'@' -f1)
  local server_part=$(echo "$url" | sed 's|trojan://[^@]*@||' | cut -d'?' -f1 | cut -d'#' -f1)
  local server=$(echo "$server_part" | cut -d':' -f1)
  local port=$(echo "$server_part" | cut -d':' -f2)
  local params=$(echo "$url" | cut -d'?' -f2 | cut -d'#' -f1)
  local sni=$(echo "$params" | grep -o 'sni=[^&]*' | cut -d'=' -f2)

  [ -z "$server" ] || [ -z "$port" ] || [ -z "$password" ] && return

  echo "  - name: node-${idx}
    type: trojan
    server: ${server}
    port: ${port}
    password: ${password}
    sni: ${sni:-$server}
    udp: true"
}

# ==================== AI Router Daemon ====================

write_ai_daemon() {
  info "Installing AI Router daemon..."

  cat > "$AI_DAEMON" << 'DAEMONEOF'
#!/bin/sh
# AI-Xray Router - Smart node selection
INSTALL_DIR="/etc/ai-xray"
API="http://127.0.0.1:9090"
SECRET=$(cat "${INSTALL_DIR}/api-secret" 2>/dev/null)
LOG="/var/log/ai-xray-router.log"
CHECK_INTERVAL=30

# Baseline tracking
BASELINE_LATENCY=0
BASELINE_SET=0
SWITCH_COOLDOWN=120
LAST_SWITCH=0

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG"; }

api_get() {
  curl -s --max-time 5 -H "Authorization: Bearer ${SECRET}" "${API}$1" 2>/dev/null
}

api_put() {
  curl -s --max-time 5 -X PUT -H "Authorization: Bearer ${SECRET}" -H "Content-Type: application/json" -d "$2" "${API}$1" 2>/dev/null
}

# Get all proxy delays
get_node_delays() {
  local proxies=$(api_get "/proxies/AI-Proxy")
  echo "$proxies" | grep -o '"name":"[^"]*"' | cut -d'"' -f4
}

# Test delay for a specific node
test_delay() {
  local node="$1"
  local result=$(api_get "/proxies/${node}/delay?timeout=3000&url=https://www.gstatic.com/generate_204")
  echo "$result" | grep -o '"delay":[0-9]*' | cut -d':' -f2
}

# Get current active node in AI-Proxy group
get_active_node() {
  local data=$(api_get "/proxies/AI-Proxy")
  echo "$data" | grep -o '"now":"[^"]*"' | cut -d'"' -f4
}

# Switch to specific node
switch_node() {
  local node="$1"
  api_put "/proxies/Proxy" "{\"name\":\"AI-Proxy\"}" >/dev/null
  log "[SWITCH] -> $node"
  LAST_SWITCH=$(date +%s)
}

# Find best node by delay
find_best_node() {
  local best_node=""
  local best_delay=99999

  local nodes=$(api_get "/proxies/AI-Proxy" | grep -o '"all":\[[^]]*\]' | grep -o '"node-[0-9]*"' | tr -d '"')

  for node in $nodes; do
    local delay=$(test_delay "$node")
    [ -z "$delay" ] && continue
    [ "$delay" -eq 0 ] && continue

    if [ "$delay" -lt "$best_delay" ]; then
      best_delay=$delay
      best_node=$node
    fi
  done

  echo "$best_node|$best_delay"
}

# Main AI routing loop
main() {
  log "[START] AI Router started"
  sleep 10  # Wait for mihomo to fully start

  while true; do
    local active=$(get_active_node)
    local now=$(date +%s)

    if [ -z "$active" ]; then
      log "[WARN] No active node detected"
      sleep $CHECK_INTERVAL
      continue
    fi

    # Test current node
    local current_delay=$(test_delay "$active")

    if [ -z "$current_delay" ] || [ "$current_delay" -eq 0 ]; then
      # Current node is dead
      log "[DEAD] $active is unresponsive"

      local best=$(find_best_node)
      local best_node=$(echo "$best" | cut -d'|' -f1)
      local best_delay=$(echo "$best" | cut -d'|' -f2)

      if [ -n "$best_node" ] && [ "$best_delay" -lt 99999 ]; then
        switch_node "$best_node"
        log "[RECOVER] $active -> $best_node (${best_delay}ms)"
      else
        log "[CRITICAL] All nodes down"
      fi

      sleep $CHECK_INTERVAL
      continue
    fi

    # Set baseline on first successful measurement
    if [ "$BASELINE_SET" -eq 0 ]; then
      BASELINE_LATENCY=$current_delay
      BASELINE_SET=1
      log "[BASELINE] Set to ${BASELINE_LATENCY}ms on $active"
    fi

    # Check if current node is degrading (2x baseline = warning)
    local threshold=$((BASELINE_LATENCY * 2))
    [ "$threshold" -lt 300 ] && threshold=300

    local cooldown_elapsed=$((now - LAST_SWITCH))

    if [ "$current_delay" -gt "$threshold" ] && [ "$cooldown_elapsed" -gt "$SWITCH_COOLDOWN" ]; then
      log "[DEGRADE] $active at ${current_delay}ms (baseline: ${BASELINE_LATENCY}ms, threshold: ${threshold}ms)"

      local best=$(find_best_node)
      local best_node=$(echo "$best" | cut -d'|' -f1)
      local best_delay=$(echo "$best" | cut -d'|' -f2)

      if [ -n "$best_node" ] && [ "$best_delay" -lt "$current_delay" ]; then
        switch_node "$best_node"
        BASELINE_LATENCY=$best_delay
        log "[OPTIMIZE] $active(${current_delay}ms) -> $best_node(${best_delay}ms)"
      fi
    else
      log "[OK] $active ${current_delay}ms (baseline: ${BASELINE_LATENCY}ms)"
    fi

    sleep $CHECK_INTERVAL
  done
}

main "$@"
DAEMONEOF

  chmod +x "$AI_DAEMON"
  ok "AI Router daemon installed"
}

# ==================== System Services ====================

setup_services() {
  info "Setting up services..."

  # mihomo init script
  cat > /etc/init.d/mihomo << 'INITEOF'
#!/bin/sh /etc/rc.common
START=99
STOP=10
USE_PROCD=1

start_service() {
  procd_open_instance
  procd_set_param command /usr/bin/mihomo -d /etc/ai-xray
  procd_set_param respawn
  procd_set_param stdout 1
  procd_set_param stderr 1
  procd_close_instance
}
INITEOF
  chmod +x /etc/init.d/mihomo

  # AI Router init script
  cat > /etc/init.d/ai-xray-router << 'INITEOF2'
#!/bin/sh /etc/rc.common
START=99
STOP=10
USE_PROCD=1

start_service() {
  procd_open_instance
  procd_set_param command /etc/ai-xray/ai-router.sh
  procd_set_param respawn
  procd_set_param stdout 1
  procd_set_param stderr 1
  procd_close_instance
}
INITEOF2
  chmod +x /etc/init.d/ai-xray-router

  # Enable and start
  /etc/init.d/mihomo enable 2>/dev/null
  /etc/init.d/mihomo start 2>/dev/null

  sleep 3

  /etc/init.d/ai-xray-router enable 2>/dev/null
  /etc/init.d/ai-xray-router start 2>/dev/null

  ok "Services started"
}

# ==================== iptables Redirect ====================

setup_redirect() {
  info "Setting up transparent proxy..."

  # Redirect TCP traffic to mihomo tproxy
  iptables -t nat -N AI_XRAY 2>/dev/null
  iptables -t nat -F AI_XRAY

  # Skip local and private
  iptables -t nat -A AI_XRAY -d 0.0.0.0/8 -j RETURN
  iptables -t nat -A AI_XRAY -d 10.0.0.0/8 -j RETURN
  iptables -t nat -A AI_XRAY -d 127.0.0.0/8 -j RETURN
  iptables -t nat -A AI_XRAY -d 169.254.0.0/16 -j RETURN
  iptables -t nat -A AI_XRAY -d 172.16.0.0/12 -j RETURN
  iptables -t nat -A AI_XRAY -d 192.168.0.0/16 -j RETURN
  iptables -t nat -A AI_XRAY -d 224.0.0.0/4 -j RETURN
  iptables -t nat -A AI_XRAY -d 240.0.0.0/4 -j RETURN

  # Redirect to redir port
  iptables -t nat -A AI_XRAY -p tcp -j REDIRECT --to-ports 7891

  # Apply to PREROUTING (LAN traffic)
  iptables -t nat -A PREROUTING -p tcp -j AI_XRAY

  ok "Transparent proxy configured"
}

# ==================== Show Result ====================

show_result() {
  echo ""
  echo -e "${GREEN}==========================================================${PLAIN}"
  echo -e "${GREEN}  AI-Xray OpenWrt Plugin installed${PLAIN}"
  echo -e "${GREEN}==========================================================${PLAIN}"
  echo ""
  echo -e "${CYAN}Mode:${PLAIN}        Transparent proxy (all LAN devices)"
  echo -e "${CYAN}Nodes:${PLAIN}       $(wc -l < ${INSTALL_DIR}/nodes.txt) loaded"
  echo -e "${CYAN}AI Router:${PLAIN}   Running"
  echo -e "${CYAN}API:${PLAIN}         ${API} (secret: ${API_SECRET})"
  echo -e "${CYAN}Dashboard:${PLAIN}   http://$(uci get network.lan.ipaddr 2>/dev/null || echo '192.168.1.1'):9090/ui"
  echo ""
  echo -e "${CYAN}Commands:${PLAIN}"
  echo "  logread -f -e ai-xray     # Watch AI Router log"
  echo "  cat /var/log/ai-xray-router.log  # Full log"
  echo "  /etc/init.d/mihomo restart       # Restart proxy"
  echo "  /etc/init.d/ai-xray-router restart  # Restart AI"
  echo ""
  echo -e "${GREEN}All devices on your network are now AI-routed.${PLAIN}"
  echo -e "${GREEN}==========================================================${PLAIN}"
}

# ==================== Main ====================

main() {
  echo -e "${CYAN}"
  echo '    _    ___      __  __                  OpenWrt'
  echo '   / \  |_ _|    \ \/ /_ __ __ _ _   _   Plugin'
  echo '  / _ \  | |_____ \  /| '\''__/ _` | | | |'
  echo ' / ___ \ | |_____ /  \| | | (_| | |_| |'
  echo '/_/   \_\___|   /_/\_\_|  \__,_|\__, |'
  echo '                                 |___/'
  echo -e "${PLAIN}"

  # Check if running on OpenWrt
  if [ ! -f /etc/openwrt_release ]; then
    warn "This doesn't look like OpenWrt. Continue anyway? [y/N]"
    read -r choice
    case $choice in
      [yY]) ;;
      *) exit 0 ;;
    esac
  fi

  # Get subscription URL
  if [ -n "$1" ]; then
    SUB_URL="$1"
  else
    echo -e "${YELLOW}Enter your subscription URL:${PLAIN}"
    read -r SUB_URL
  fi

  [ -z "$SUB_URL" ] && fail "Subscription URL is required"

  mkdir -p "$INSTALL_DIR"
  > "${INSTALL_DIR}/nodes.txt"

  detect_arch
  install_mihomo
  parse_subscription "$SUB_URL"
  generate_config
  write_ai_daemon
  setup_services
  setup_redirect
  show_result
}

main "$@"
