# AI-Xray

AI驱动的跨境电商网络加速器。

**定位**：不是翻墙工具，是跨境电商网络加速器。默认白名单锁死 TikTok Business / Amazon Seller / Google Ads / Shopify 等平台。

---

## 两种模式

### 免费模式（零成本）
- ✅ 无需VPS，无需花钱
- ✅ 使用 Cloudflare 全球节点
- ✅ 5分钟部署完成
- ⚠️ 速度一般（共享节点）

### 专业模式（需要VPS）
- ✅ 自有海外VPS，独享带宽
- ✅ VLESS + Reality + Vision 协议
- ✅ 一行命令安装
- ⚠️ 需要购买VPS（$5-20/月）

---

## 免费模式部署

我们推荐使用成熟稳定的 [edgetunnel](https://github.com/cmliu/edgetunnel) 项目（27k+ stars）。

### 快速部署

1. **Fork 项目**：访问 [edgetunnel](https://github.com/cmliu/edgetunnel)，点击右上角 Fork
2. **部署到 CF Pages**：
   - 登录 [Cloudflare Dashboard](https://dash.cloudflare.com)
   - Workers & Pages → 创建 → Pages → 连接到 Git
   - 选择 edgetunnel 项目 → 开始设置
   - 环境变量添加：`ADMIN` = 你的管理员密码
   - 保存并部署
3. **访问后台**：`https://你的项目.pages.dev/admin`

详细教程：[edgetunnel 官方文档](https://github.com/cmliu/edgetunnel#readme)

---

## 专业模式部署

### 前置要求

- ✅ 海外 VPS（推荐：美国/日本/新加坡）
- ✅ 系统：Debian 10+ / Ubuntu 20.04+ / CentOS 7+
- ✅ 端口 443 未被占用
- ✅ Root 权限

### 一键安装

SSH 登录 VPS，执行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ScientificInternet/AI-Xray/main/install-simple.sh)
```

### 安装过程

脚本自动完成：
1. ✅ 检测系统环境
2. ✅ 安装依赖（curl/jq/sqlite3）
3. ✅ 启用 BBR 加速
4. ✅ 安装 Xray-core
5. ✅ 生成 Reality 密钥
6. ✅ 根据 VPS 位置选择最佳伪装目标
7. ✅ 配置白名单路由
8. ✅ 启动服务

### 安装完成

脚本输出：

```
========================================
  AI-Xray Installation Complete
========================================

Server: 1.2.3.4:443
UUID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
Public Key: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
Short ID: xxxxxxxxxxxxxxxx
SNI: addons.mozilla.org

VLESS Link:
vless://xxxxxxxx@1.2.3.4:443?encryption=none&flow=xtls-rprx-vision...
```

复制 **VLESS Link** 到客户端即可使用。

---

## 客户端推荐

| 平台 | 客户端 | 下载 |
|------|--------|------|
| Windows | v2rayN | [GitHub](https://github.com/2dust/v2rayN/releases) |
| macOS | V2rayU | [GitHub](https://github.com/yanue/V2rayU/releases) |
| iOS | Shadowrocket | App Store（需美区账号） |
| Android | v2rayNG | [GitHub](https://github.com/2dust/v2rayNG/releases) |

---

## 白名单说明

默认白名单仅允许访问跨境电商平台：

| 平台 | 域名 |
|------|------|
| TikTok Business | business.tiktok.com, ads.tiktok.com, seller.tiktok.com |
| Amazon Seller | sellercentral.amazon.com, advertising.amazon.com |
| Google Ads | ads.google.com, merchants.google.com |
| Meta Business | business.facebook.com |
| Shopify | admin.shopify.com, accounts.shopify.com |
| AI 服务 | api.openai.com, chat.openai.com, claude.ai, gemini.google.com |

### 修改白名单

编辑配置文件：

```bash
nano /usr/local/etc/xray/config.json
```

找到 `routing.rules[0].domain` 数组，添加或删除域名。

修改后重启：

```bash
systemctl restart xray
```

⚠️ **法律提示**：本项目定位为跨境电商网络加速器。删除白名单限制后，法律责任由用户自行承担。

---

## 常见问题

### 免费模式速度慢？

Cloudflare 节点是共享的，速度取决于网络运营商和访问时段。如需稳定高速，使用专业模式。

### 专业模式连不上？

检查：
1. VPS 防火墙是否开放 443 端口
2. Xray 服务状态：`systemctl status xray`
3. 查看日志：`journalctl -u xray -n 50`

### 如何卸载？

```bash
systemctl stop xray
systemctl disable xray
rm -rf /etc/ai-xray
rm -f /usr/local/bin/xray
```

---

## VPS 推荐

| 商家 | 线路 | 价格 | 适合 |
|------|------|------|------|
| [搬瓦工](https://bandwagonhost.com) | CN2 GIA | $49.99/年 | 电信用户 |
| [DMIT](https://www.dmit.io) | CMI | $6.9/月 | 移动用户 |
| [Vultr](https://www.vultr.com) | 普通线路 | $5/月 | 预算有限 |

---

## 技术支持

- GitHub Issues: https://github.com/ScientificInternet/AI-Xray/issues
- 协议：MIT License

---

## 安全提示

1. ✅ 不要分享你的 UUID 和密钥
2. ✅ 定期更新 Xray 版本
3. ✅ 不要在公共场合讨论使用细节
4. ✅ 遵守当地法律法规

---

## 致谢

- [Xray-core](https://github.com/XTLS/Xray-core) - 核心协议
- [edgetunnel](https://github.com/cmliu/edgetunnel) - CF Workers 免费模式
- [mack-a/v2ray-agent](https://github.com/mack-a/v2ray-agent) - 安装脚本参考

---

**AI-Xray** - 让跨境电商更简单。
