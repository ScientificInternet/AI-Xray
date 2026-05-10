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
        # CentOS/RHEL: 关防火墙和SELinux
        systemctl stop firewalld 2>/dev/null || true
        systemctl disable firewalld 2>/dev/null || true
        setenforce 0 2>/dev/null || true
        sed -i "s/^SELINUX=enforcing/SELINUX=disabled/" /etc/selinux/config 2>/dev/null || true
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
    DNS_OK=0; NET_OK=0
    getent ahosts "$DOMAIN" >/dev/null 2>&1 && DNS_OK=1
    curl -fsS --max-time 5 https://1.1.1.1 >/dev/null 2>&1 && NET_OK=1
    [[ $DNS_OK -eq 1 ]] && colorEcho $GREEN "✓ DNS解析正常" || colorEcho $RED "✗ DNS解析失败"
    [[ $NET_OK -eq 1 ]] && colorEcho $GREEN "✓ 出站网络正常" || colorEcho $RED "✗ 出站网络不通"
    LATENCY=$(ping -c 3 google.com 2>/dev/null | tail -1 | awk -F'/' '{print $5}') || true
    [[ -n "$LATENCY" ]] && colorEcho $GREEN "✓ 延迟: ${LATENCY}ms" || colorEcho $YELLOW "△ 无法测延迟"
    BBR=$(sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | grep bbr || true)
    [[ -n "$BBR" ]] && colorEcho $GREEN "✓ BBR已开启" || colorEcho $YELLOW "△ BBR未开启，将自动开启"
}

#=== 4. 安装依赖 =============================================================
installDeps() {
    echo ""; colorEcho $BLUE "安装依赖..."
    if [[ "$PMT" == "apt" ]]; then
        apt update -qq
    elif [[ "$PMT" == "yum" ]]; then
        # CentOS 7需要EPEL来获取nginx
        yum install -y epel-release 2>/dev/null || true
    fi
    for pkg in curl wget unzip jq openssl socat nginx tar; do
        if ! $CMD_INSTALL "$pkg"; then
            colorEcho $RED "依赖安装失败: $pkg"; exit 1
        fi
    done
    # CentOS 7 nginx特殊处理：如果EPEL也没有，用nginx官方源
    if ! which nginx &>/dev/null && [[ "$PMT" == "yum" ]]; then
        cat > /etc/yum.repos.d/nginx.repo << 'NGINXREPO'
[nginx-stable]
name=nginx stable repo
baseurl=https://nginx.org/packages/centos/$releasever/$basearch/
gpgcheck=1
enabled=1
repo_gpgcheck=1
gpgkey=https://nginx.org/keys/nginx_signing.key
NGINXREPO
        $CMD_INSTALL nginx 2>/dev/null
    fi
    systemctl enable nginx 2>/dev/null || true
    colorEcho $GREEN "✓ 依赖安装完成"
}

#=== 5. 安装Xray =============================================================
installXray() {
    echo ""; colorEcho $BLUE "安装Xray..."
    XRAY_URL="https://raw.githubusercontent.com/XTLS/Xray-install/e741a4f56d368afbb9e5be3361b40c4552d3710d/install-release.sh"
    XRAY_SHA256="7f70c95f6b418da8b4f4883343d602964915e28748993870fd554383afdbe555"
    tmp_xray=$(mktemp)
    curl -fsSL "$XRAY_URL" -o "$tmp_xray"
    echo "${XRAY_SHA256}  ${tmp_xray}" | sha256sum -c - || {
        colorEcho $RED "Xray安装脚本校验失败"; rm -f "$tmp_xray"; exit 1
    }
    bash "$tmp_xray" install
    rm -f "$tmp_xray"
    systemctl enable xray 2>/dev/null || true
    colorEcho $GREEN "✓ Xray安装完成"
}

#=== 6. 申请证书 =============================================================
installCert() {
    echo ""; colorEcho $BLUE "申请证书..."
    # 先检查端口占用
    res=$(ss -ntlp 2>/dev/null | grep -E ':(80|443)\s' || true)
    if [[ -n "$res" ]]; then
        colorEcho $RED "80/443端口已被占用："
        echo "$res"
        colorEcho $YELLOW "请释放端口后重试"; exit 1
    fi
    systemctl stop nginx 2>/dev/null || true
    systemctl stop xray 2>/dev/null || true
    sleep 2

    $CMD_INSTALL socat openssl 2>/dev/null
    if [[ "$PMT" == "yum" ]]; then
        $CMD_INSTALL cronie 2>/dev/null
        systemctl start crond 2>/dev/null || true; systemctl enable crond 2>/dev/null || true
    else
        $CMD_INSTALL cron 2>/dev/null
        systemctl start cron 2>/dev/null || true; systemctl enable cron 2>/dev/null || true
    fi

    ACME_URL="https://raw.githubusercontent.com/acmesh-official/acme.sh/3.1.3/acme.sh"
    ACME_SHA256="adc76e222a4cde93d6390f41618df7796549ed2b6057239376df08e235ae4574"
    tmp_acme=$(mktemp)
    curl -fsSL "$ACME_URL" -o "$tmp_acme"
    echo "${ACME_SHA256}  ${tmp_acme}" | sha256sum -c - || {
        colorEcho $RED "acme.sh校验失败"; rm -f "$tmp_acme"; exit 1
    }
    install -m 0755 "$tmp_acme" /usr/local/bin/acme.sh
    rm -f "$tmp_acme"
    /usr/local/bin/acme.sh --set-default-ca --server letsencrypt 2>/dev/null || true
    /usr/local/bin/acme.sh --issue -d ${DOMAIN} --keylength ec-256 --standalone --force

    mkdir -p /root/.acme.sh/${DOMAIN}_ecc
    /usr/local/bin/acme.sh --install-cert -d ${DOMAIN} --ecc \
        --key-file /root/.acme.sh/${DOMAIN}_ecc/${DOMAIN}.key \
        --fullchain-file /root/.acme.sh/${DOMAIN}_ecc/fullchain.cer \
        --reloadcmd "systemctl reload nginx"

    [[ -f /root/.acme.sh/${DOMAIN}_ecc/fullchain.cer ]] || {
        colorEcho $RED "证书申请失败"; exit 1
    }
    colorEcho $GREEN "✓ 证书申请成功"
}

#=== 7. 生成配置 =============================================================
generateConfig() {
    echo ""; colorEcho $BLUE "生成配置..."

    XRAY_PORT=$(shuf -i 10000-65535 -n 1)
    while ss -lnt 2>/dev/null | awk '{print $4}' | grep -q ":${XRAY_PORT}$"; do
        XRAY_PORT=$(shuf -i 10000-65535 -n 1)
    done
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
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "domain": ["domain:google.com","domain:facebook.com","domain:tiktok.com","domain:x.com","domain:pinterest.com","domain:openai.com","domain:claude.ai"],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "port": "0-65535",
        "outboundTag": "blocked"
      }
    ]
  }
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

    # 删除nginx默认站点，避免server块冲突
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
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
    SITE_HTML=$(curl -fsSL --max-time 30 "https://aixray.fluxrouter.net/generate?type=${SITE_TYPE}&lang=en" 2>/dev/null) || true
    if [[ ${#SITE_HTML} -gt 500 ]] && echo "$SITE_HTML" | grep -qi "<html"; then
        echo "$SITE_HTML" > ${SITE_DIR}/index.html
        colorEcho $GREEN "✓ AI专属伪装站已生成"
        return 0
    fi

    # Level 2: 公开模板池 + 本地渲染
    colorEcho $YELLOW "AI生成临时不可用，使用本地模板..."
    TEMPLATES_URL="https://raw.githubusercontent.com/ScientificInternet/ai-xray-sites/main"
    MANIFEST=$(curl -fsSL --max-time 10 "${TEMPLATES_URL}/manifest.json" 2>/dev/null) || true
    if [[ -n "$MANIFEST" ]]; then
        TEMPLATE_COUNT=$(echo "$MANIFEST" | jq '.templates | length' 2>/dev/null) || true
        if [[ "$TEMPLATE_COUNT" -gt 0 ]]; then
            RANDOM_INDEX=$((RANDOM % TEMPLATE_COUNT))
            TEMPLATE_NAME=$(echo "$MANIFEST" | jq -r ".templates[$RANDOM_INDEX].name") || true
            TEMPLATE_HASH=$(echo "$MANIFEST" | jq -r ".templates[$RANDOM_INDEX].sha256") || true
            curl -fsSL --max-time 15 "${TEMPLATES_URL}/templates/${TEMPLATE_NAME}.tar.gz" -o /tmp/template.tar.gz
            if [[ -f /tmp/template.tar.gz ]]; then
                ACTUAL_HASH=$(sha256sum /tmp/template.tar.gz | cut -d' ' -f1) || true
                if [[ "$ACTUAL_HASH" == "$TEMPLATE_HASH" ]]; then
                    mkdir -p /tmp/ai-xray-template
                    if tar xzf /tmp/template.tar.gz -C /tmp/ai-xray-template/ 2>/dev/null; then
                        SEED="$(hostname)-$(date +%s)-${RANDOM}"
                        find /tmp/ai-xray-template -name '*.html' -exec sed -i "s/{{SITE_TITLE}}/Documentation Portal/g; s/{{BUILD_ID}}/$(echo $SEED | md5sum | cut -c1-8)/g; s/{{YEAR}}/$(date +%Y)/g" {} \;
                        cp -r /tmp/ai-xray-template/* ${SITE_DIR}/
                        rm -rf /tmp/template.tar.gz /tmp/ai-xray-template/
                        colorEcho $GREEN "✓ 本地模板伪装站已生成"
                        return 0
                    else
                        colorEcho $YELLOW "模板解压失败，使用默认站点"
                    fi
                fi
            fi
            rm -f /tmp/template.tar.gz
        fi
    fi

    # Level 3: 静态占位页
    colorEcho $YELLOW "启用静态占位页..."
    cat > ${SITE_DIR}/index.html << 'FALLBACK'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>Site Maintenance</title>
<style>body{font-family:Arial,sans-serif;text-align:center;padding:80px 20px;color:#555}
h1{font-size:2em;color:#333}</style></head>
<body><h1>Site Maintenance</h1><p>This site is currently under maintenance.</p></body></html>
FALLBACK
    colorEcho $GREEN "✓ 静态占位页已启用"
}

#=== 8.5 白名单 + TOS ========================================================
setupWhitelist() {
    # 写入白名单文件
    cat > /usr/local/etc/xray/whitelist.txt << 'WLIST'
google.com
facebook.com
tiktok.com
x.com
pinterest.com
openai.com
claude.ai
WLIST

    # 写入TOS
    cat > /usr/local/etc/xray/TOS.txt << 'TOSEOF'
TERMS OF SERVICE — AI-Xray Cross-border Accelerator

AI-Xray is designed as a network accelerator for cross-border
e-commerce and AI productivity platforms. The default configuration
restricts access to authorized business platforms only.

By removing or modifying the default whitelist, you acknowledge:

1. You are solely responsible for all network traffic routed
   through this software after modification.
2. You will comply with all applicable local and international
   laws and regulations.
3. The developers and contributors of AI-Xray bear no liability
   for any use beyond the original cross-border business purpose.
4. This software is provided "AS IS" without warranty of any kind.

If you do not agree, do not modify the whitelist.
TOSEOF

    colorEcho $GREEN "✓ 白名单 + TOS 已就绪"
}

#=== 9. 开启BBR ==============================================================
enableBBR() {
    echo ""; colorEcho $BLUE "开启BBR..."
    # 尝试加载BBR模块（部分旧内核不支持）
    modprobe tcp_bbr 2>/dev/null || true
    # 检查BBR是否可用
    if sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -q bbr; then
        cat > /etc/sysctl.d/99-ai-xray-bbr.conf << 'BBRCFG'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
BBRCFG
        sysctl --system >/dev/null 2>&1 || true
        colorEcho $GREEN "✓ BBR已开启"
    else
        colorEcho $YELLOW "△ 内核不支持BBR，跳过"
    fi
}

#=== 10. 配置测试 ==============================================================
test_configs() {
    nginx -t || return 1
    /usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json >/dev/null 2>&1 || return 1
    return 0
}

#=== 11. 启动服务 ============================================================
startServices() {
    echo ""; colorEcho $BLUE "测试配置..."
    if ! test_configs; then
        colorEcho $RED "配置测试失败，未启动服务"
        exit 1
    fi
    echo ""; colorEcho $BLUE "启动服务..."
    systemctl restart xray 2>/dev/null || true; systemctl restart nginx 2>/dev/null || true
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

#=== 12. 保存信息 =============================================================
saveInfo() {
    IP=$(curl -s4m5 https://ip.gs || curl -s4m5 https://ifconfig.me || echo "unknown")
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
  "siteType": "${SITE_TYPE}",
  "managedPaths": {
    "xrayConfig": "/usr/local/etc/xray/config.json",
    "nginxConfig": "/etc/nginx/conf.d/ai-xray.conf",
    "siteDir": "/usr/share/nginx/ai-xray",
    "certDir": "/root/.acme.sh/${DOMAIN}_ecc",
    "whitelist": "/usr/local/etc/xray/whitelist.txt",
    "tosFile": "/usr/local/etc/xray/TOS.txt"
  }
}
EOF
}

#=== 13. 输出信息 ============================================================
showInfo() {
    IP=$(curl -s4m5 https://ip.gs || curl -s4m5 https://ifconfig.me || echo "unknown")

    # 生成VMess链接
    raw="{\"v\":\"2\",\"ps\":\"AI-Xray-${DOMAIN}\",\"add\":\"${DOMAIN}\",\"port\":\"443\",\"id\":\"${UUID}\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"${WS_PATH}\",\"tls\":\"tls\"}"
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
    echo ""
    echo -e "  ${YELLOW}默认已启用跨境平台白名单（7个域名）${PLAIN}"
    echo -e "  ${YELLOW}输入 ai-xray 进入管理菜单修改白名单${PLAIN}"
    echo -e "${GREEN}========================================${PLAIN}"
}

#=== 14. 安装管理命令 ========================================================
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
    echo "  7) 白名单管理"
    echo "  8) 卸载"
    echo "  0) 退出"
    echo ""
    read -p "请选择[0-8]: " choice

    case $choice in
        1) show_info ;;
        2) regenerate_site ;;
        3) update_xray ;;
        4) restart_services ;;
        5) view_logs ;;
        6) show_status ;;
        7) whitelist_menu ;;
        8) uninstall ;;
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
        raw="{\"v\":\"2\",\"ps\":\"AI-Xray-${DOMAIN}\",\"add\":\"${DOMAIN}\",\"port\":\"443\",\"id\":\"${UUID}\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"${WSPATH}\",\"tls\":\"tls\"}"
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
    SITE_TYPE=$(jq -r .siteType "$INFO_FILE" 2>/dev/null || echo "1")
    SITE_HTML=$(curl -fsSL --max-time 30 "https://aixray.fluxrouter.net/generate?type=${SITE_TYPE}&lang=en" 2>/dev/null) || true
    if [[ ${#SITE_HTML} -gt 500 ]] && echo "$SITE_HTML" | grep -qi "<html"; then
        echo "$SITE_HTML" > ${SITE_DIR}/index.html
        colorEcho $GREEN "✓ 伪装站已刷新"
    else
        colorEcho $RED "✗ 生成失败，稍后重试"
    fi
}

update_xray() {
    colorEcho $BLUE "检查Xray更新..."
    XRAY_URL="https://raw.githubusercontent.com/XTLS/Xray-install/e741a4f56d368afbb9e5be3361b40c4552d3710d/install-release.sh"
    XRAY_SHA="7f70c95f6b418da8b4f4883343d602964915e28748993870fd554383afdbe555"
    tmp_x=$(mktemp)
    curl -fsSL "$XRAY_URL" -o "$tmp_x"
    echo "${XRAY_SHA}  ${tmp_x}" | sha256sum -c - || {
        colorEcho $RED "Xray校验失败"; rm -f "$tmp_x"; return 1
    }
    bash "$tmp_x" install && rm -f "$tmp_x"
    systemctl restart xray
    colorEcho $GREEN "✓ Xray已更新"
}

restart_services() {
    nginx -t || { colorEcho $RED "nginx配置测试失败"; return 1; }
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

    if [[ -f "$INFO_FILE" ]]; then
        XCFG=$(jq -r '.managedPaths.xrayConfig // empty' "$INFO_FILE")
        NCFG=$(jq -r '.managedPaths.nginxConfig // empty' "$INFO_FILE")
        SDIR=$(jq -r '.managedPaths.siteDir // empty' "$INFO_FILE")
        CDIR=$(jq -r '.managedPaths.certDir // empty' "$INFO_FILE")
        WL=$(jq -r '.managedPaths.whitelist // empty' "$INFO_FILE")
        TOSF=$(jq -r '.managedPaths.tosFile // empty' "$INFO_FILE")

        systemctl stop xray 2>/dev/null || true
        rm -f "$XCFG" "$NCFG" "$WL" "$TOSF"
        rm -rf "$SDIR" "$CDIR" /etc/ai-xray
    fi

    rm -f /usr/local/bin/ai-xray
    colorEcho $GREEN "✓ 卸载完成"
}

rebuild_routing() {
    python3 << 'PYEOF'
import json

config_path = "/usr/local/etc/xray/config.json"
whitelist_path = "/usr/local/etc/xray/whitelist.txt"

with open(config_path, "r") as f:
    config = json.load(f)

try:
    with open(whitelist_path, "r") as f:
        domains = [line.strip() for line in f if line.strip()]
except FileNotFoundError:
    domains = []

if domains:
    config["routing"] = {
        "domainStrategy": "AsIs",
        "rules": [
            {
                "type": "field",
                "domain": [f"domain:{d}" for d in domains],
                "outboundTag": "direct"
            },
            {
                "type": "field",
                "port": "0-65535",
                "outboundTag": "blocked"
            }
        ]
    }
else:
    config["routing"] = {
        "domainStrategy": "AsIs",
        "rules": [
            {
                "type": "field",
                "port": "0-65535",
                "outboundTag": "direct"
            }
        ]
    }

with open(config_path, "w") as f:
    json.dump(config, f, indent=2)
PYEOF

    systemctl restart xray 2>/dev/null || killall -SIGHUP xray 2>/dev/null
}

whitelist_menu() {
    WHITELIST="/usr/local/etc/xray/whitelist.txt"
    DEFAULT_DOMAINS="google.com facebook.com tiktok.com x.com pinterest.com openai.com claude.ai"

    while true; do
        echo ""; echo -e "${BLUE}白名单管理${PLAIN}"; echo ""
        echo "当前白名单："
        if [[ -f "$WHITELIST" ]] && [[ -s "$WHITELIST" ]]; then
            nl -w2 -s". " "$WHITELIST"
        else
            colorEcho $YELLOW "  (空 — 不限制流量)"
        fi
        echo ""
        echo "  a. 添加域名"
        echo "  d. 删除单个域名（输入编号）"
        echo "  r. 全部删除（解锁全部流量）"
        echo "  s. 恢复默认白名单"
        echo "  0. 返回主菜单"
        echo ""
        read -p "请选择: " wl_choice

        case $wl_choice in
            a)
                read -p "请输入域名（例如 shopify.com）: " new_domain
                [[ -z "$new_domain" ]] && continue
                echo "$new_domain" >> "$WHITELIST"
                colorEcho $GREEN "✓ 已添加 ${new_domain}"
                rebuild_routing
                ;;
            d)
                read -p "请输入要删除的编号: " del_num
                domain=$(sed -n "${del_num}p" "$WHITELIST" 2>/dev/null)
                [[ -z "$domain" ]] && { colorEcho $RED "无效编号"; continue; }
                echo ""; colorEcho $YELLOW "即将删除：${domain}"; echo ""
                cat /usr/local/etc/xray/TOS.txt 2>/dev/null
                echo ""; read -p "输入 YES 确认删除，其他任意键取消: " confirm
                if [[ "$confirm" == "YES" ]]; then
                    sed -i "${del_num}d" "$WHITELIST"
                    colorEcho $GREEN "✓ 已删除"
                    rebuild_routing
                else
                    colorEcho $YELLOW "已取消"
                fi
                ;;
            r)
                echo ""; colorEcho $RED "即将删除所有白名单条目。"
                echo "删除后 AI-Xray 将变为不限制流量的通用加速器。"; echo ""
                cat /usr/local/etc/xray/TOS.txt 2>/dev/null
                echo ""; read -p "输入 YES 确认删除所有白名单，其他任意键取消: " confirm
                if [[ "$confirm" == "YES" ]]; then
                    > "$WHITELIST"
                    colorEcho $GREEN "✓ 已清空白名单"
                    rebuild_routing
                else
                    colorEcho $YELLOW "已取消"
                fi
                ;;
            s)
                read -p "将恢复为出厂默认白名单（7个域名），确认？(y/n) " confirm
                if [[ "$confirm" == "y" ]] || [[ "$confirm" == "Y" ]]; then
                    echo "$DEFAULT_DOMAINS" | tr ' ' '\n' > "$WHITELIST"
                    colorEcho $GREEN "✓ 已恢复默认白名单"
                    rebuild_routing
                fi
                ;;
            0) return 0 ;;
            *) colorEcho $RED "无效选项" ;;
        esac
    done
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

    # 安装前备份已有配置
    echo ""; colorEcho $BLUE "备份已有配置..."
    mkdir -p /etc/ai-xray/backup 2>/dev/null || true
    [[ -f /usr/local/etc/xray/config.json ]] && cp /usr/local/etc/xray/config.json /etc/ai-xray/backup/config.json.bak.$(date +%s) 2>/dev/null || true
    [[ -f /etc/nginx/conf.d/ai-xray.conf ]] && cp /etc/nginx/conf.d/ai-xray.conf /etc/ai-xray/backup/ai-xray.conf.bak.$(date +%s) 2>/dev/null || true

    installDeps
    installXray
    installCert
    generateConfig
    generateSite
    enableBBR
    setupWhitelist
    saveInfo
    installManager
    startServices
    showInfo
}

main
