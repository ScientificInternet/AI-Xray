#!/bin/bash
# AI-Xray Professional Installer with VPS Quality Check
# https://github.com/ScientificInternet/AI-Xray

# 等待1秒避免curl输出冲突
sleep 1

# Colors
red='\e[91m'
green='\e[92m'
yellow='\e[93m'
cyan='\e[96m'
blue='\e[94m'
none='\e[0m'

# Error handler
error_exit() {
    local message="$1"
    echo ""
    echo -e "${red}========================================${none}"
    echo -e "${red}Installation Failed${none}"
    echo -e "${red}========================================${none}"
    echo ""
    echo -e "${red}Error: ${message}${none}"
    echo ""
    echo -e "${yellow}Please report this issue:${none}"
    echo -e "${cyan}https://github.com/ScientificInternet/AI-Xray/issues${none}"
    echo ""
    echo -e "${yellow}Include the following information:${none}"
    echo -e "  • Error message: ${message}"
    echo -e "  • OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2 2>/dev/null || echo 'Unknown')"
    echo -e "  • Kernel: $(uname -r)"
    echo ""
    exit 1
}

echo -e "${cyan}========================================${none}"
echo -e "${cyan}AI-Xray Professional Installer${none}"
echo -e "${cyan}Cross-border E-commerce Accelerator${none}"
echo -e "${cyan}========================================${none}"
echo ""

# Check root
if [[ $EUID -ne 0 ]]; then
   error_exit "This script must be run as root"
fi

# Detect system
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS=$ID
else
    error_exit "Cannot detect operating system"
fi

echo -e "${green}✓ System: $OS${none}"

# ==================== VPS Quality Check ====================
echo ""
echo -e "${cyan}========================================${none}"
echo -e "${cyan}Step 1: VPS Quality Check${none}"
echo -e "${cyan}========================================${none}"
echo ""
echo -e "${yellow}Checking your VPS quality for cross-border e-commerce...${none}"
echo -e "${yellow}This will take 2-3 minutes.${none}"
echo ""

# Download vpscheck
VPSCHECK_URL="https://raw.githubusercontent.com/adsorgcn/vpscheck/main/vpscheck.sh"
VPSCHECK_TMP="/tmp/vpscheck_$$.sh"

if ! curl -fsSL "$VPSCHECK_URL" -o "$VPSCHECK_TMP"; then
    echo -e "${yellow}Warning: Cannot download vpscheck, skipping quality check${none}"
    SKIP_CHECK=1
fi

if [[ -z "$SKIP_CHECK" ]]; then
    # Run key checks: AI services + IP info + Route
    echo -e "${cyan}Running AI services check...${none}"
    bash "$VPSCHECK_TMP" -r 5 -u > /tmp/vps_ai_check.txt 2>&1
    
    echo -e "${cyan}Running IP analysis...${none}"
    bash "$VPSCHECK_TMP" -r 10 > /tmp/vps_ip_check.txt 2>&1
    
    echo -e "${cyan}Running route quality check...${none}"
    # 延迟参考表
    declare -A LATENCY_REF=(
        ["guangzhou_hongkong"]="5|10"
        ["guangzhou_singapore"]="45|60"
        ["guangzhou_tokyo"]="60|80"
        ["guangzhou_losangeles"]="150|180"
        ["shanghai_hongkong"]="35|50"
        ["shanghai_singapore"]="65|85"
        ["shanghai_tokyo"]="27|40"
        ["shanghai_losangeles"]="127|150"
        ["beijing_hongkong"]="45|60"
        ["beijing_singapore"]="75|95"
        ["beijing_tokyo"]="40|55"
        ["beijing_losangeles"]="140|170"
        ["chengdu_hongkong"]="40|55"
        ["chengdu_singapore"]="60|80"
        ["chengdu_tokyo"]="80|100"
        ["chengdu_losangeles"]="170|200"
        ["wuhan_hongkong"]="30|45"
        ["wuhan_singapore"]="60|80"
        ["wuhan_tokyo"]="50|70"
        ["wuhan_losangeles"]="150|180"
    )
    
    # 检测源地区
    IP_INFO=$(curl -s ipinfo.io 2>/dev/null || curl -s ip-api.com/json 2>/dev/null)
    CITY=$(echo "$IP_INFO" | grep -i "city\|region" | head -1 | grep -oP '(?<=:")[^"]+' | tr '[:upper:]' '[:lower:]')
    
    case "$CITY" in
        *guangzhou*|*shenzhen*|*dongguan*|*foshan*) SOURCE_REGION="guangzhou" ;;
        *shanghai*|*hangzhou*|*nanjing*|*suzhou*) SOURCE_REGION="shanghai" ;;
        *beijing*|*tianjin*) SOURCE_REGION="beijing" ;;
        *chengdu*|*chongqing*) SOURCE_REGION="chengdu" ;;
        *wuhan*|*changsha*) SOURCE_REGION="wuhan" ;;
        *) SOURCE_REGION="shanghai" ;;  # 默认上海
    esac
    
    # 测试延迟
    declare -A TARGETS=(
        ["hongkong"]="hk.cloudflare.com"
        ["singapore"]="sg.cloudflare.com"
        ["tokyo"]="jp.cloudflare.com"
        ["losangeles"]="lax.cloudflare.com"
    )
    
    declare -A ROUTE_RESULTS
    ROUTE_SCORE=0
    
    for target_name in "${!TARGETS[@]}"; do
        target_host="${TARGETS[$target_name]}"
        latency=$(ping -c 3 -W 2 "$target_host" 2>/dev/null | grep 'avg' | awk -F'/' '{print $5}' | cut -d'.' -f1)
        
        if [[ -n "$latency" && "$latency" != "0" ]]; then
            key="${SOURCE_REGION}_${target_name}"
            ref="${LATENCY_REF[$key]}"
            
            if [[ -n "$ref" ]]; then
                standard=$(echo "$ref" | cut -d'|' -f1)
                tolerance=$(echo "$ref" | cut -d'|' -f2)
                
                # 判断路由质量
                if [[ $latency -le $tolerance ]]; then
                    ROUTE_RESULTS[$target_name]="direct|$latency|$standard"
                    ((ROUTE_SCORE++))
                else
                    excess=$((latency - standard))
                    if [[ $excess -gt 100 ]]; then
                        ROUTE_RESULTS[$target_name]="detour_major|$latency|$standard"
                    else
                        ROUTE_RESULTS[$target_name]="detour_minor|$latency|$standard"
                    fi
                fi
            fi
        fi
    done
    
    echo -e "${cyan}Running streaming unlock check...${none}"
    curl -fsSL https://raw.githubusercontent.com/lmc999/RegionRestrictionCheck/main/check.sh | bash -s -- -M 4 -E en > /tmp/vps_streaming_check.txt 2>&1
    
    # Parse results
    echo ""
    echo -e "${cyan}========================================${none}"
    echo -e "${cyan}VPS Quality Report / VPS 质量报告${none}"
    echo -e "${cyan}========================================${none}"
    
    # Check AI services
    CHATGPT_OK=$(grep -i "chatgpt" /tmp/vps_ai_check.txt | grep -i "解锁\|yes\|可用" | wc -l)
    CLAUDE_OK=$(grep -i "claude" /tmp/vps_ai_check.txt | grep -i "解锁\|yes\|可用" | wc -l)
    GEMINI_OK=$(grep -i "gemini" /tmp/vps_ai_check.txt | grep -i "解锁\|yes\|可用" | wc -l)
    
    # Check streaming services
    NETFLIX_OK=$(grep -i "netflix" /tmp/vps_streaming_check.txt | grep -i "yes\|unlock\|解锁" | wc -l)
    DISNEY_OK=$(grep -i "disney" /tmp/vps_streaming_check.txt | grep -i "yes\|unlock\|解锁" | wc -l)
    YOUTUBE_OK=$(grep -i "youtube premium" /tmp/vps_streaming_check.txt | grep -i "yes\|unlock\|解锁" | wc -l)
    SPOTIFY_OK=$(grep -i "spotify" /tmp/vps_streaming_check.txt | grep -i "yes\|unlock\|解锁" | wc -l)
    
    # Check IP type
    IP_TYPE=$(grep -i "IP类型\|IP Type" /tmp/vps_ip_check.txt | head -1)
    
    # Display results
    echo ""
    echo -e "${blue}AI Services / AI 服务:${none}"
    [[ $CHATGPT_OK -gt 0 ]] && echo -e "  ${green}✓ ChatGPT${none}" || echo -e "  ${red}✗ ChatGPT${none}"
    [[ $CLAUDE_OK -gt 0 ]] && echo -e "  ${green}✓ Claude${none}" || echo -e "  ${red}✗ Claude${none}"
    [[ $GEMINI_OK -gt 0 ]] && echo -e "  ${green}✓ Gemini${none}" || echo -e "  ${red}✗ Gemini${none}"
    
    echo ""
    echo -e "${blue}Streaming Services / 流媒体服务:${none}"
    [[ $NETFLIX_OK -gt 0 ]] && echo -e "  ${green}✓ Netflix${none}" || echo -e "  ${red}✗ Netflix${none}"
    [[ $DISNEY_OK -gt 0 ]] && echo -e "  ${green}✓ Disney+${none}" || echo -e "  ${red}✗ Disney+${none}"
    [[ $YOUTUBE_OK -gt 0 ]] && echo -e "  ${green}✓ YouTube Premium${none}" || echo -e "  ${red}✗ YouTube Premium${none}"
    [[ $SPOTIFY_OK -gt 0 ]] && echo -e "  ${green}✓ Spotify${none}" || echo -e "  ${red}✗ Spotify${none}"
    
    echo ""
    echo -e "${blue}Route Quality / 路由质量 (from ${SOURCE_REGION}):${none}"
    for target in "${!ROUTE_RESULTS[@]}"; do
        result="${ROUTE_RESULTS[$target]}"
        IFS='|' read -r status latency standard <<< "$result"
        
        case "$status" in
            direct)
                echo -e "  ${green}✓ ${target}: ${latency}ms${none} (Standard: ${standard}ms)"
                ;;
            detour_minor)
                echo -e "  ${yellow}⚠ ${target}: ${latency}ms${none} (Standard: ${standard}ms, +$((latency - standard))ms)"
                echo -e "    ${yellow}Domestic detour / 国内绕路${none}"
                ;;
            detour_major)
                echo -e "  ${red}✗ ${target}: ${latency}ms${none} (Standard: ${standard}ms, +$((latency - standard))ms)"
                echo -e "    ${red}Major detour detected / 严重绕路${none}"
                ;;
        esac
    done
    
    echo ""
    echo -e "${blue}IP Information / IP 信息:${none}"
    echo -e "  $IP_TYPE"
    
    # Overall recommendation
    echo ""
    echo -e "${cyan}========================================${none}"
    SCORE=0
    [[ $CHATGPT_OK -gt 0 ]] && ((SCORE++))
    [[ $CLAUDE_OK -gt 0 ]] && ((SCORE++))
    [[ $GEMINI_OK -gt 0 ]] && ((SCORE++))
    [[ $NETFLIX_OK -gt 0 ]] && ((SCORE++))
    [[ $DISNEY_OK -gt 0 ]] && ((SCORE++))
    [[ $ROUTE_SCORE -ge 3 ]] && ((SCORE+=2))  # 路由质量好加 2 分
    [[ $ROUTE_SCORE -ge 2 ]] && ((SCORE+=1))  # 路由质量一般加 1 分
    
    if [[ $SCORE -ge 6 ]]; then
        echo -e "${green}✓ Excellent VPS / 优秀 VPS${none}"
        echo -e "${green}  Recommended for / 推荐用于:${none}"
        echo -e "${green}  • Cross-border e-commerce / 跨境电商${none}"
        echo -e "${green}  • AI tools / AI 工具${none}"
        echo -e "${green}  • Streaming services / 流媒体服务${none}"
    elif [[ $SCORE -ge 3 ]]; then
        echo -e "${yellow}⚠ Good VPS / 良好 VPS${none}"
        echo -e "${yellow}  Suitable for most tasks / 适合大多数任务${none}"
        echo -e "${yellow}  Some services may be restricted / 部分服务可能受限${none}"
    else
        echo -e "${red}✗ Poor VPS / 较差 VPS${none}"
        echo -e "${red}  Consider a different provider / 建议更换服务商${none}"
        echo -e "${red}  Recommended: US/EU native IP / 推荐：美欧原生 IP${none}"
        echo ""
    fi
    
    # 提示详细路由检测
    if [[ $ROUTE_SCORE -lt 3 ]]; then
        echo ""
        echo -e "${yellow}For detailed route analysis / 详细路由分析:${none}"
        echo -e "  ${cyan}curl -sL https://nxtrace.org/nt | bash${none}"
        echo -e "  ${cyan}nexttrace google.com${none}"
    fi
    
    # Cleanup
    rm -f "$VPSCHECK_TMP" /tmp/vps_*_check.txt
fi

# ==================== Install Dependencies ====================
echo ""
echo -e "${cyan}========================================${none}"
echo -e "${cyan}Step 2: Install Dependencies${none}"
echo -e "${cyan}========================================${none}"
echo ""

case $OS in
    ubuntu|debian)
        apt-get update -qq
        apt-get install -y curl wget unzip openssl >/dev/null 2>&1
        ;;
    centos|rhel|rocky|almalinux)
        yum install -y curl wget unzip openssl >/dev/null 2>&1
        ;;
    *)
        error_exit "Unsupported OS: $OS"
        ;;
esac

echo -e "${green}✓ Dependencies installed${none}"

# ==================== Install Xray ====================
echo ""
echo -e "${cyan}========================================${none}"
echo -e "${cyan}Step 3: Install Xray-core${none}"
echo -e "${cyan}========================================${none}"
echo ""

# Install Xray-core with pinned version and checksum verification
XRAY_INSTALL_COMMIT="e741a4f5"
XRAY_INSTALL_SHA256="7f70c95f6b418da8b4f4883343d602964915e28748993870fd554383afdbe555"
XRAY_INSTALL_URL="https://raw.githubusercontent.com/XTLS/Xray-install/${XRAY_INSTALL_COMMIT}/install-release.sh"
XRAY_INSTALL_TMP="/tmp/xray-install-$$.sh"

echo -e "${cyan}Downloading Xray installer (pinned: ${XRAY_INSTALL_COMMIT})...${none}"
if ! curl -fsSL "$XRAY_INSTALL_URL" -o "$XRAY_INSTALL_TMP"; then
    error_exit "Failed to download Xray installer"
    return
fi

echo -e "${cyan}Verifying checksum...${none}"
echo "${XRAY_INSTALL_SHA256}  ${XRAY_INSTALL_TMP}" | sha256sum -c - >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
    rm -f "$XRAY_INSTALL_TMP"
    error_exit "Checksum verification failed"
fi

echo -e "${cyan}Installing Xray-core...${none}"
bash "$XRAY_INSTALL_TMP" install >/dev/null 2>&1
rm -f "$XRAY_INSTALL_TMP"

if ! command -v xray >/dev/null 2>&1; then
    error_exit "Xray installation failed"
fi

xray_version=$(xray version 2>/dev/null | head -1 | awk '{print $2}')

# ==================== Generate Keys ====================
echo ""
echo -e "${cyan}========================================${none}"
echo -e "${cyan}Step 4: Generate Reality Keys${none}"
echo -e "${cyan}========================================${none}"
echo ""

keys=$(xray x25519)
PRIVATE_KEY=$(echo "$keys" | grep "Private" | awk '{print $NF}')
PUBLIC_KEY=$(echo "$keys" | grep "Public" | awk '{print $NF}')
UUID=$(xray uuid)
SHORT_ID=$(openssl rand -hex 8)

echo -e "${green}✓ Keys generated${none}"

# ==================== Detect Server Info ====================
echo ""
echo -e "${cyan}========================================${none}"
echo -e "${cyan}Step 5: Detect Server Information${none}"
echo -e "${cyan}========================================${none}"
echo ""

SERVER_IP=$(curl -s --max-time 3 https://api.ipify.org || curl -s --max-time 3 https://ifconfig.me || echo "YOUR_SERVER_IP")
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

echo -e "${green}✓ Server IP: $SERVER_IP${none}"
echo -e "${green}✓ Region: $REGION${none}"
echo -e "${green}✓ SNI: $DEST${none}"

# ==================== Write Configuration ====================
echo ""
echo -e "${cyan}========================================${none}"
echo -e "${cyan}Step 6: Configure Xray Reality${none}"
echo -e "${cyan}========================================${none}"
echo ""

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
        "domain": [
          "geosite:category-ads-all",
          "geosite:category-ads"
        ],
        "outboundTag": "block"
      },
      {
        "type": "field",
        "domain": [
          "domain:tiktok.com",
          "domain:amazon.com",
          "domain:google.com",
          "domain:googleapis.com",
          "domain:facebook.com",
          "domain:fbcdn.net",
          "domain:shopify.com",
          "domain:openai.com",
          "domain:anthropic.com",
          "domain:claude.ai",
          "domain:stripe.com",
          "domain:paypal.com",
          "domain:aliexpress.com",
          "domain:ebay.com",
          "domain:etsy.com",
          "domain:walmart.com",
          "domain:cloudflare.com",
          "domain:amazonaws.com",
          "domain:github.com",
          "domain:netflix.com",
          "domain:disneyplus.com",
          "domain:youtube.com",
          "domain:spotify.com",
          "domain:hulu.com",
          "domain:perplexity.ai",
          "domain:mistral.ai",
          "domain:cohere.com",
          "domain:huggingface.co"
        ],
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

echo -e "${green}✓ Configuration written${none}"

# ==================== Enable BBR ====================
echo ""
echo -e "${cyan}========================================${none}"
echo -e "${cyan}Step 7: Enable BBR Congestion Control${none}"
echo -e "${cyan}========================================${none}"
echo ""

sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
sysctl -p >/dev/null 2>&1

echo -e "${green}✓ BBR enabled${none}"

# ==================== Start Service ====================
echo ""
echo -e "${cyan}========================================${none}"
echo -e "${cyan}Step 8: Start Xray Service${none}"
echo -e "${cyan}========================================${none}"
echo ""

systemctl restart xray
systemctl enable xray >/dev/null 2>&1

if systemctl is-active --quiet xray; then
    echo -e "${green}✓ Xray service started${none}"
else
    error_exit "Xray service failed to start. Check logs: journalctl -u xray -n 50"
fi

# ==================== Installation Complete ====================
echo ""
echo -e "${green}Installation Complete!${none}"
echo -e "${green}========================================${none}"
echo ""
echo -e "${cyan}Server Information:${none}"
echo -e "  Address: ${green}$SERVER_IP:443${none}"
echo -e "  UUID: ${green}$UUID${none}"
echo -e "  Public Key: ${green}$PUBLIC_KEY${none}"
echo -e "  Short ID: ${green}$SHORT_ID${none}"
echo -e "  SNI: ${green}$DEST${none}"
echo ""
echo -e "${cyan}VLESS Link:${none}"
echo "vless://${UUID}@${SERVER_IP}:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${DEST}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none#AI-Xray"
echo ""
echo -e "${cyan}Whitelist (Cross-border E-commerce):${none}"
echo -e "  ${green}✓${none} TikTok Business / Ads / Seller"
echo -e "  ${green}✓${none} Amazon Seller Central / Advertising"
echo -e "  ${green}✓${none} Google Ads / Merchant Center"
echo -e "  ${green}✓${none} Facebook Business / Ads"
echo -e "  ${green}✓${none} Shopify Admin"
echo -e "  ${green}✓${none} ChatGPT / Claude / Gemini"
echo ""
echo -e "${yellow}Note:${none} Only whitelisted domains are allowed by default."
echo -e "${yellow}Edit whitelist:${none} nano /usr/local/etc/xray/config.json"
echo ""
# ==================== Interactive Whitelist Configuration ====================

whitelist_interactive_config() {
    local CONFIG_FILE="/usr/local/etc/xray/config.json"
    
    while true; do
        echo ""
        echo -e "${cyan}========================================${none}"
        echo -e "${cyan}  Whitelist Configuration / 白名单配置${none}"
        echo -e "${cyan}========================================${none}"
        echo ""
        
        # Count domains
        DOMAIN_COUNT=$(jq -r '.routing.rules[] | select(.outboundTag=="direct") | .domain | length' "$CONFIG_FILE" 2>/dev/null || echo "0")
        
        echo -e "${green}Current whitelist ($DOMAIN_COUNT domains) / 当前白名单（${DOMAIN_COUNT}个域名）${none}"
        echo ""
        echo -e "${yellow}Options / 选项：${none}"
        echo -e "  ${cyan}[v]${none} View all domains / 查看所有域名"
        echo -e "  ${cyan}[d]${none} Delete domain / 删除域名"
        echo -e "  ${cyan}[a]${none} Add domain / 添加域名"
        echo -e "  ${cyan}[c]${none} Clear all / 清空全部"
        echo -e "  ${cyan}[k]${none} Keep current settings / 保持当前设置"
        echo ""
        echo -ne "${yellow}Choose an option / 请选择 [k]: ${none}"
        read -r CHOICE
        
        # Default to keep
        CHOICE=${CHOICE:-k}
        
        case "$CHOICE" in
            v|V)
                echo ""
                echo -e "${cyan}All domains / 所有域名：${none}"
                jq -r '.routing.rules[] | select(.outboundTag=="direct") | .domain[]' "$CONFIG_FILE" | nl
                ;;
            d|D)
                echo ""
                echo -e "${cyan}Current domains / 当前域名：${none}"
                jq -r '.routing.rules[] | select(.outboundTag=="direct") | .domain[]' "$CONFIG_FILE" | nl
                echo ""
                echo -ne "${yellow}Enter number to delete / 输入要删除的编号: ${none}"
                read -r NUM
                
                if [[ "$NUM" =~ ^[0-9]+$ ]]; then
                    INDEX=$((NUM - 1))
                    DOMAIN=$(jq -r ".routing.rules[] | select(.outboundTag==\"direct\") | .domain[$INDEX]" "$CONFIG_FILE")
                    
                    if [[ -n "$DOMAIN" && "$DOMAIN" != "null" ]]; then
                        jq "(.routing.rules[] | select(.outboundTag==\"direct\") | .domain) |= del(.[$INDEX])" "$CONFIG_FILE" > /tmp/config.tmp
                        mv /tmp/config.tmp "$CONFIG_FILE"
                        echo -e "${green}✓ Deleted / 已删除: $DOMAIN${none}"
                        systemctl restart xray
                        echo -e "${green}✓ Service restarted / 服务已重启${none}"
                    else
                        echo -e "${red}Invalid number / 无效编号${none}"
                    fi
                else
                    echo -e "${red}Invalid input / 无效输入${none}"
                fi
                ;;
            a|A)
                echo ""
                echo -ne "${yellow}Enter domain to add / 输入要添加的域名: ${none}"
                read -r DOMAIN
                
                if [[ "$DOMAIN" =~ ^[A-Za-z0-9.-]+$ ]]; then
                    jq --arg domain "domain:$DOMAIN" '(.routing.rules[] | select(.outboundTag=="direct") | .domain) += [$domain]' "$CONFIG_FILE" > /tmp/config.tmp
                    mv /tmp/config.tmp "$CONFIG_FILE"
                    echo -e "${green}✓ Added / 已添加: domain:$DOMAIN${none}"
                    systemctl restart xray
                    echo -e "${green}✓ Service restarted / 服务已重启${none}"
                else
                    echo -e "${red}Invalid domain format / 域名格式无效${none}"
                fi
                ;;
            c|C)
                echo ""
                echo -e "${red}========================================${none}"
                echo -e "${red}  WARNING: Terms of Service / 警告：服务条款${none}"
                echo -e "${red}========================================${none}"
                echo ""
                echo -e "${yellow}You are about to remove all domain restrictions.${none}"
                echo -e "${yellow}您即将移除所有域名限制。${none}"
                echo ""
                echo -e "${yellow}This will allow access to ANY website through this proxy.${none}"
                echo -e "${yellow}这将允许通过此代理访问任何网站。${none}"
                echo ""
                echo -e "${cyan}Legal Notice / 法律声明：${none}"
                echo -e "  • This software is designed for cross-border e-commerce"
                echo -e "    本软件专为跨境电商设计"
                echo -e "  • Removing restrictions is at your own risk"
                echo -e "    移除限制风险自负"
                echo -e "  • You are responsible for compliance with local laws"
                echo -e "    您需遵守当地法律"
                echo -e "  • The author assumes no liability for misuse"
                echo -e "    作者不承担滥用责任"
                echo ""
                echo -ne "${yellow}Type 'YES' or 'Y' to confirm / 输入 YES 或 Y 确认: ${none}"
                read -r CONFIRM
                
                if [[ "$CONFIRM" == "YES" || "$CONFIRM" == "Y" ]]; then
                    # Remove the whitelist rule, keep only ad blocking
                    jq 'del(.routing.rules[] | select(.outboundTag=="direct"))' "$CONFIG_FILE" > /tmp/config.tmp
                    mv /tmp/config.tmp "$CONFIG_FILE"
                    echo ""
                    echo -e "${green}✓ All restrictions removed / 所有限制已移除${none}"
                    echo -e "${green}✓ Configuration updated / 配置已更新${none}"
                    systemctl restart xray
                    echo -e "${green}✓ Service restarted / 服务已重启${none}"
                    echo ""
                    echo -e "${yellow}Your proxy now has NO domain restrictions.${none}"
                    echo -e "${yellow}您的代理现在没有任何域名限制。${none}"
                    return 0
                else
                    echo -e "${yellow}Cancelled / 已取消${none}"
                fi
                ;;
            k|K|"")
                echo ""
                echo -e "${green}✓ Keeping current settings / 保持当前设置${none}"
                return 0
                ;;
            *)
                echo -e "${red}Invalid option / 无效选项${none}"
                ;;
        esac
    done
}

# Call interactive configuration
whitelist_interactive_config

echo ""
echo -e "${green}========================================${none}"
echo -e "${green}  Setup Complete / 安装完成${none}"
echo -e "${green}========================================${none}"
echo ""
