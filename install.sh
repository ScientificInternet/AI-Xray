#!/bin/bash
#=============================================================================
# AI-Xray v2.0 — 跨境电商加速器
# VMESS + WS + TLS + CDN · AI伪装站 · 一行命令全自动安装
#=============================================================================

set -e

#=== 颜色 ===================================================================
RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"
BLUE="\033[36m"; PLAIN="\033[0m"
cyan="$BLUE"; green="$GREEN"; yellow="$YELLOW"; red="$RED"; none="$PLAIN"

#=== 全局变量 ===============================================================
XRAY_PORT=""; UUID=""; WS_PATH=""; DOMAIN=""; SITE_TYPE=""
PMT=""; CMD_INSTALL=""; CMD_REMOVE=""; CMD_UPGRADE=""
INFO_FILE="/etc/ai-xray/info.json"
SITE_DIR="/usr/share/nginx/ai-xray"

colorEcho() { echo -e "${1}${@:2}${PLAIN}"; }

#=== 1. 系统检测 =============================================================
checkSystem() {
    [[ $EUID -ne 0 ]] && colorEcho $RED "请以root身份执行" && exit 1
    if which apt &>/dev/null; then
        PMT="apt"; CMD_INSTALL="apt install -y"; CMD_REMOVE="apt remove -y"
        CMD_UPGRADE="apt update; apt upgrade -y; apt autoremove -y"
    elif which yum &>/dev/null; then
        PMT="yum"; CMD_INSTALL="yum install -y"; CMD_REMOVE="yum remove -y"
        CMD_UPGRADE="yum update -y"
    else
        colorEcho $RED "不受支持的系统"; exit 1
    fi
    which systemctl &>/dev/null || { colorEcho $RED "系统版本过低"; exit 1; }
    colorEcho $GREEN "✓ 系统检测通过"
}

#=== 2. 用户输入 =============================================================
getData() {
    echo ""; echo -e "${BLUE}AI-Xray 跨境电商加速器 v2.0${PLAIN}"; echo ""
    while [[ -z "$DOMAIN" ]]; do
        read -p "请输入你的域名（必须已解析到本服务器）: " DOMAIN
    done
    DOMAIN=${DOMAIN,,}
    colorEcho $BLUE "域名：$DOMAIN"

    echo ""; echo "请选择伪装站类型[默认：1]:"
    echo "  1) AI协议文档站（AI自动生成，推荐）"
    echo "  2) 加密工具站"
    echo "  3) 学生福利导航站"
    echo "  4) 不需要伪装站"
    read -p "选择[1]: " SITE_TYPE
    SITE_TYPE=${SITE_TYPE:-1}
    colorEcho $BLUE "伪装站类型：$SITE_TYPE"
}

#=== 3. VPS质量检测 ===========================================================
vps_check() {
    echo ""; colorEcho $BLUE "VPS质量检测..."
    AI_OK=0
    curl -sI --max-time 5 "https://api.openai.com" >/dev/null 2>&1 && AI_OK=1
    curl -sI --max-time 5 "https://api.anthropic.com" >/dev/null 2>&1 && AI_OK=1
    curl -sI --max-time 5 "https://generativelanguage.googleapis.com" >/dev/null 2>&1 && AI_OK=1
    [[ $AI_OK -eq 1 ]] && colorEcho $GREEN "✓ AI服务连通" || colorEcho $RED "✗ AI服务不通"
    LATENCY=$(ping -c 3 google.com 2>/dev/null | tail -1 | awk -F'/' '{print $5}')
    [[ -n "$LATENCY" ]] && colorEcho $GREEN "✓ 延迟: ${LATENCY}ms" || colorEcho $YELLOW "△ 无法测延迟"
    BBR=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep bbr)
    [[ -n "$BBR" ]] && colorEcho $GREEN "✓ BBR已开启" || colorEcho $YELLOW "△ BBR未开启，将自动开启"
}

#=== 4. 安装依赖 =============================================================
installDeps() {
    echo ""; colorEcho $BLUE "安装依赖..."
    if [[ "$PMT" == "apt" ]]; then
        apt update -qq
    fi
    for pkg in curl wget unzip jq openssl socat nginx; do
        $CMD_INSTALL $pkg 2>/dev/null
    done
    systemctl enable nginx 2>/dev/null
    colorEcho $GREEN "✓ 依赖安装完成"
}

#=== 5. 安装Xray =============================================================
installXray() {
    echo ""; colorEcho $BLUE "安装Xray..."
    bash -c "$(curl -sL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install 2>/dev/null
    systemctl enable xray 2>/dev/null
    colorEcho $GREEN "✓ Xray安装完成"
}

#=== 6. 申请证书 =============================================================
installCert() {
    echo ""; colorEcho $BLUE "申请证书..."
    systemctl stop nginx 2>/dev/null || true
    systemctl stop xray 2>/dev/null || true

    # 检查端口
    res=$(ss -ntlp | grep -E ':80 |:443 ' 2>/dev/null)
    if [[ -n "$res" ]]; then
        colorEcho $RED "80/443端口被占用，请先释放"
        echo "$res"; exit 1
    fi

    $CMD_INSTALL socat openssl 2>/dev/null
    if [[ "$PMT" == "yum" ]]; then
        $CMD_INSTALL cronie 2>/dev/null
        systemctl start crond 2>/dev/null; systemctl enable crond 2>/dev/null
    else
        $CMD_INSTALL cron 2>/dev/null
        systemctl start cron 2>/dev/null; systemctl enable cron 2>/dev/null
    fi

    curl -sL https://get.acme.sh | sh
    source ~/.bashrc
    ~/.acme.sh/acme.sh --upgrade --auto-upgrade 2>/dev/null
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    ~/.acme.sh/acme.sh --issue -d ${DOMAIN} --keylength ec-256 --standalone --force

    mkdir -p /root/.acme.sh/${DOMAIN}_ecc
    ~/.acme.sh/acme.sh --install-cert -d ${DOMAIN} --ecc \
        --key-file /root/.acme.sh/${DOMAIN}_ecc/${DOMAIN}.key \
        --fullchain-file /root/.acme.sh/${DOMAIN}_ecc/fullchain.cer

    [[ -f /root/.acme.sh/${DOMAIN}_ecc/fullchain.cer ]] || {
        colorEcho $RED "证书申请失败"; exit 1
    }
    colorEcho $GREEN "✓ 证书申请成功"
}

#=== 7. 生成配置 =============================================================
generateConfig() {
    echo ""; colorEcho $BLUE "生成配置..."

    XRAY_PORT=$((10000 + RANDOM % 55535))
    UUID=$(cat /proc/sys/kernel/random/uuid)
    len=$(shuf -i5-12 -n1)
    ws=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w $len | head -n 1)
    WS_PATH="/$ws"

    mkdir -p /usr/local/etc/xray
    cat > /usr/local/etc/xray/config.json << XEOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [{
    "tag": "vmess-ws",
    "port": ${XRAY_PORT},
    "listen": "127.0.0.1",
    "protocol": "vmess",
    "settings": {
      "clients": [{"id": "${UUID}"}]
    },
    "streamSettings": {
      "network": "ws",
      "wsSettings": {"path": "${WS_PATH}"}
    }
  }],
  "outbounds": [
    {"protocol": "freedom", "tag": "direct"},
    {"protocol": "blackhole", "tag": "blocked"}
  ]
}
XEOF

    mkdir -p /etc/nginx/conf.d 2>/dev/null || true
    cat > /etc/nginx/conf.d/ai-xray.conf << NEOF
server {
    listen 443 ssl http2;
    server_name ${DOMAIN};
    ssl_certificate /root/.acme.sh/${DOMAIN}_ecc/fullchain.cer;
    ssl_certificate_key /root/.acme.sh/${DOMAIN}_ecc/${DOMAIN}.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location ${WS_PATH} {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:${XRAY_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location / {
        root ${SITE_DIR};
        index index.html;
        try_files \$uri \$uri/ =404;
    }
}
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$host\$request_uri;
}
NEOF

    # 如果nginx默认用sites-available，创建软链
    if [[ -d /etc/nginx/sites-available ]]; then
        ln -sf /etc/nginx/conf.d/ai-xray.conf /etc/nginx/sites-available/ai-xray
        ln -sf /etc/nginx/sites-available/ai-xray /etc/nginx/sites-enabled/ai-xray 2>/dev/null || true
    fi

    colorEcho $GREEN "✓ 配置生成完成"
}

#=== 8. 伪装站生成（三层fallback） ============================================
generateSite() {
    mkdir -p ${SITE_DIR}

    if [[ "$SITE_TYPE" == "4" ]]; then
        echo '<html><body>.</body></html>' > ${SITE_DIR}/index.html
        colorEcho $GREEN "✓ 跳过伪装站"
        return 0
    fi

    # Level 1: AI实时生成
    echo ""; colorEcho $BLUE "正在生成专属伪装站..."
    SITE_HTML=$(curl -fsSL --max-time 30 "https://aixray.fluxrouter.net/generate?type=${SITE_TYPE}&lang=en" 2>/dev/null)
    if [[ $? -eq 0 ]] && [[ ${#SITE_HTML} -gt 500 ]]; then
        echo "$SITE_HTML" > ${SITE_DIR}/index.html
        colorEcho $GREEN "✓ AI专属伪装站已生成"
        return 0
    fi

    # Level 2: 公开模板池 + 本地渲染
    colorEcho $YELLOW "AI生成临时不可用，使用本地模板..."
    TEMPLATES_URL="https://raw.githubusercontent.com/ScientificInternet/ai-xray-sites/main"
    MANIFEST=$(curl -fsSL --max-time 10 "${TEMPLATES_URL}/manifest.json" 2>/dev/null)
    if [[ $? -eq 0 ]]; then
        TEMPLATE_COUNT=$(echo "$MANIFEST" | jq '.templates | length' 2>/dev/null)
        if [[ "$TEMPLATE_COUNT" -gt 0 ]]; then
            RANDOM_INDEX=$((RANDOM % TEMPLATE_COUNT))
            TEMPLATE_NAME=$(echo "$MANIFEST" | jq -r ".templates[$RANDOM_INDEX].name")
            TEMPLATE_HASH=$(echo "$MANIFEST" | jq -r ".templates[$RANDOM_INDEX].sha256")
            curl -fsSL --max-time 15 "${TEMPLATES_URL}/templates/${TEMPLATE_NAME}.tar.gz" -o /tmp/template.tar.gz
            if [[ -f /tmp/template.tar.gz ]]; then
                ACTUAL_HASH=$(sha256sum /tmp/template.tar.gz | cut -d' ' -f1)
                if [[ "$ACTUAL_HASH" == "$TEMPLATE_HASH" ]]; then
                    mkdir -p /tmp/ai-xray-template
                    tar xzf /tmp/template.tar.gz -C /tmp/ai-xray-template/
                    SEED="$(hostname)-$(date +%s)-${RANDOM}"
                    find /tmp/ai-xray-template -name '*.html' -exec sed -i "s/{{SITE_TITLE}}/I-Lang Protocol v3.${RANDOM:0:1}.${RANDOM:0:2}/g; s/{{BUILD_ID}}/$(echo $SEED | md5sum | cut -c1-8)/g; s/{{YEAR}}/$(date +%Y)/g" {} \;
                    cp -r /tmp/ai-xray-template/* ${SITE_DIR}/
                    rm -rf /tmp/template.tar.gz /tmp/ai-xray-template/
                    colorEcho $GREEN "✓ 本地模板伪装站已生成"
                    return 0
                fi
            fi
            rm -f /tmp/template.tar.gz
        fi
    fi

    # Level 3: jiami.dog 反代
    colorEcho $YELLOW "启用临时默认站点..."
    cat > ${SITE_DIR}/index.html << 'FALLBACK'
<!DOCTYPE html><html><head><meta http-equiv="refresh" content="0;url=https://jiami.dog"></head><body></body></html>
FALLBACK
    colorEcho $GREEN "✓ 临时默认站点已启用"
}

#=== 9. 开启BBR ==============================================================
enableBBR() {
    echo ""; colorEcho $BLUE "开启BBR..."
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1
    colorEcho $GREEN "✓ BBR已开启"
}

#=== 10. 启动服务 ============================================================
startServices() {
    echo ""; colorEcho $BLUE "启动服务..."
    systemctl restart xray; systemctl restart nginx
    sleep 2
    if systemctl is-active --quiet xray && systemctl is-active --quiet nginx; then
        colorEcho $GREEN "✓ Xray + Nginx 运行中"
    else
        colorEcho $RED "✗ 服务启动失败，请检查日志"
        colorEcho $YELLOW "  journalctl -u xray --no-pager -n 20"
        colorEcho $YELLOW "  journalctl -u nginx --no-pager -n 20"
        exit 1
    fi
}

#=== 11. 保存信息 =============================================================
saveInfo() {
    IP=$(curl -s4m5 https://ip.gs || echo "unknown")
    mkdir -p /etc/ai-xray
    cat > ${INFO_FILE} << EOF
{
  "version": "2.0.0",
  "domain": "${DOMAIN}",
  "port": 443,
  "uuid": "${UUID}",
  "protocol": "vmess",
  "network": "ws",
  "tls": "tls",
  "wsPath": "${WS_PATH}",
  "ip": "${IP}",
  "siteType": "${SITE_TYPE}"
}
EOF
}

#=== 12. 输出信息 ============================================================
showInfo() {
    IP=$(curl -s4m5 https://ip.gs || echo "unknown")

    # 生成VMess链接
    raw="{\"v\":\"2\",\"ps\":\"AI-Xray-${DOMAIN}\",\"add\":\"${IP}\",\"port\":\"443\",\"id\":\"${UUID}\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"${WS_PATH}\",\"tls\":\"tls\"}"
    link=$(echo -n "$raw" | base64 -w 0)
    link="vmess://${link}"

    echo ""; echo -e "${GREEN}========================================${PLAIN}"
    echo -e "${GREEN}AI-Xray 安装完成 v2.0${PLAIN}"
    echo -e "${GREEN}========================================${PLAIN}"
    echo ""
    echo -e "  域名：      ${RED}${DOMAIN}${PLAIN}"
    echo -e "  端口：      ${RED}443${PLAIN}"
    echo -e "  UUID：      ${RED}${UUID}${PLAIN}"
    echo -e "  协议：      ${RED}VMESS + WS + TLS${PLAIN}"
    echo -e "  WS路径：    ${RED}${WS_PATH}${PLAIN}"
    echo -e "  伪装站：    ${RED}https://${DOMAIN}${PLAIN}"
    echo ""
    echo -e "${BLUE}  VMess链接：${PLAIN}"
    echo -e "${RED}  ${link}${PLAIN}"
    echo ""
    echo -e "  客户端教程：${BLUE}https://ssr.dedyn.io${PLAIN}"
    echo ""
    echo -e "  可选：Cloudflare开启橙色云朵(Proxied)"
    echo -e "        SSL模式选Full(strict)"
    echo ""
    echo -e "  管理命令：${BLUE}ai-xray${PLAIN}"
    echo -e "${GREEN}========================================${PLAIN}"
}

#=== 13. 安装管理命令 ========================================================
installManager() {
    cat > /usr/local/bin/ai-xray << 'MGRSCRIPT'
#!/bin/bash
INFO_FILE="/etc/ai-xray/info.json"
SITE_DIR="/usr/share/nginx/ai-xray"

RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; BLUE="\033[36m"; PLAIN="\033[0m"
colorEcho() { echo -e "${1}${@:2}${PLAIN}"; }

show_menu() {
    echo ""; echo -e "${BLUE}AI-Xray 管理菜单 v2.0${PLAIN}"; echo ""
    echo "  1) 查看连接信息"
    echo "  2) 重新生成伪装站"
    echo "  3) 更新Xray内核"
    echo "  4) 重启服务"
    echo "  5) 查看日志"
    echo "  6) 查看状态"
    echo "  7) 卸载"
    echo "  0) 退出"
    echo ""
    read -p "请选择[0-7]: " choice

    case $choice in
        1) show_info ;;
        2) regenerate_site ;;
        3) update_xray ;;
        4) restart_services ;;
        5) view_logs ;;
        6) show_status ;;
        7) uninstall ;;
        0) exit 0 ;;
        *) colorEcho $RED "无效选项" && show_menu ;;
    esac
}

show_info() {
    if [[ -f "$INFO_FILE" ]]; then
        echo ""; colorEcho $BLUE "连接信息："
        DOMAIN=$(jq -r .domain "$INFO_FILE")
        UUID=$(jq -r .uuid "$INFO_FILE")
        WSPATH=$(jq -r .wsPath "$INFO_FILE")
        IP=$(jq -r .ip "$INFO_FILE")
        raw="{\"v\":\"2\",\"ps\":\"AI-Xray-${DOMAIN}\",\"add\":\"${IP}\",\"port\":\"443\",\"id\":\"${UUID}\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"${WSPATH}\",\"tls\":\"tls\"}"
        link=$(echo -n "$raw" | base64 -w 0)
        echo -e "  域名:   ${GREEN}${DOMAIN}${PLAIN}"
        echo -e "  端口:   ${GREEN}443${PLAIN}"
        echo -e "  UUID:   ${GREEN}${UUID}${PLAIN}"
        echo -e "  WS路径: ${GREEN}${WSPATH}${PLAIN}"
        echo -e "  VMess:  ${GREEN}vmess://${link}${PLAIN}"
    else
        colorEcho $RED "未安装AI-Xray"
    fi
}

regenerate_site() {
    colorEcho $BLUE "正在重新生成伪装站..."
    SITE_HTML=$(curl -fsSL --max-time 30 "https://aixray.fluxrouter.net/generate?type=1&lang=en" 2>/dev/null)
    if [[ $? -eq 0 ]] && [[ ${#SITE_HTML} -gt 500 ]]; then
        echo "$SITE_HTML" > ${SITE_DIR}/index.html
        colorEcho $GREEN "✓ 伪装站已刷新"
    else
        colorEcho $RED "✗ 生成失败，稍后重试"
    fi
}

update_xray() {
    colorEcho $BLUE "检查Xray更新..."
    bash -c "$(curl -sL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install 2>/dev/null
    systemctl restart xray
    colorEcho $GREEN "✓ Xray已更新"
}

restart_services() {
    systemctl restart xray; systemctl restart nginx
    colorEcho $GREEN "✓ 服务已重启"
}

view_logs() {
    echo ""; colorEcho $BLUE "Xray日志（最近30行）："
    journalctl -u xray --no-pager -n 30
    echo ""; colorEcho $BLUE "Nginx错误日志（最近10行）："
    tail -10 /var/log/nginx/error.log 2>/dev/null || echo "无日志"
}

show_status() {
    echo ""; echo -n "Xray: "
    systemctl is-active --quiet xray && echo -e "${GREEN}运行中${PLAIN}" || echo -e "${RED}未运行${PLAIN}"
    echo -n "Nginx: "
    systemctl is-active --quiet nginx && echo -e "${GREEN}运行中${PLAIN}" || echo -e "${RED}未运行${PLAIN}"
    echo -n "443端口: "
    ss -tlnp | grep -q ':443 ' && echo -e "${GREEN}监听中${PLAIN}" || echo -e "${RED}未监听${PLAIN}"
}

uninstall() {
    echo ""; colorEcho $YELLOW "确认卸载AI-Xray? [y/N]"
    read -p "" confirm
    [[ "$confirm" != "y" ]] && [[ "$confirm" != "Y" ]] && return

    systemctl stop xray 2>/dev/null; systemctl stop nginx 2>/dev/null
    systemctl disable xray 2>/dev/null; systemctl disable nginx 2>/dev/null
    rm -f /usr/local/bin/xray /usr/local/etc/xray/config.json
    rm -f /etc/nginx/conf.d/ai-xray.conf /etc/nginx/sites-available/ai-xray /etc/nginx/sites-enabled/ai-xray
    rm -rf /usr/share/nginx/ai-xray /etc/ai-xray
    rm -f /usr/local/bin/ai-xray
    colorEcho $GREEN "✓ 卸载完成"
}

show_menu
MGRSCRIPT
    chmod +x /usr/local/bin/ai-xray
    colorEcho $GREEN "✓ 管理命令已安装: ai-xray"
}

#=== 主流程 ==================================================================
main() {
    checkSystem
    getData
    vps_check
    installDeps
    installXray
    installCert
    generateConfig
    generateSite
    enableBBR
    startServices
    saveInfo
    installManager
    showInfo
}

main
