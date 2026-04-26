# AI-Xray

AI驱动的跨境电商网络加速器。GFW检测前自动换脸，越用越聪明。

AI-powered Xray manager with pre-emptive identity rotation. Code is open, model is the moat.

---

## 为什么需要 AI-Xray

现有所有代理脚本装完就是静态配置。被封了等人修，IP不行靠运气。

AI-Xray 不一样：

- 被封前就换脸（变色龙，不是凤凰）
- 安装时自动检测IP质量和解锁状态
- 自动选择最佳伪装目标
- 流量行为自动整形，看起来像正常网站访问
- 模型越用越聪明，社区越大越精准

---

## 两种模式

### 模式一：免费模式（零成本）

无需VPS，无需花钱。使用 Cloudflare 全球节点作为代理。

- 注册免费 CF 账号
- 部署一个 JS 文件到 Workers/Pages
- AI 自动优选最快的 CF IP
- 速度一般但永久免费，GFW 封不了 CF

适合：先体验、轻度使用、预算为零的用户

### 模式二：专业模式（需要VPS）

自有海外 VPS，部署 VLESS + Reality + Vision 协议。

- 一行命令安装
- AI 守卫 7x24 监测，自动换脸
- Reality 协议抗 GFW 能力最强
- 速度取决于你的 VPS 线路

适合：跨境电商从业者、需要稳定高速访问 TikTok/Amazon/Google Ads 的用户

---

## 快速开始

### 免费模式

1. Fork 本项目到你的 GitHub
2. 登录 [Cloudflare Dashboard](https://dash.cloudflare.com) → Pages → 连接 Git → 选择 AI-Xray → 部署
3. 设置环境变量：`UUID` = 你的自定义密钥（[在线生成](https://www.uuidgenerator.net/)）
4. 访问 `https://你的项目.pages.dev/你的UUID` 获取节点配置

详见下方「免费模式安装流程」。

### 专业模式

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ScientificInternet/AI-Xray/main/install.sh)
```

脚本会自动引导你完成安装。

---

## 免费模式安装流程

零 VPS、零成本，使用 Cloudflare 全球 CDN 节点。

### 第一步：部署到 Cloudflare Pages

**方式一：GitHub 连接（推荐）**

1. 点击本页右上角 Fork
2. 登录 [Cloudflare Dashboard](https://dash.cloudflare.com)
3. 左侧菜单 → Workers & Pages → 创建 → Pages → 连接到 Git
4. 选择 Fork 的 AI-Xray 仓库 → 保存并部署
5. 部署完成后进入 设置 → 环境变量 → 添加变量：
   - 变量名：`UUID`
   - 值：自定义密钥（任意 UUID 格式字符串）
6. 返回 部署 → 重新部署一次使变量生效

**方式二：直接上传**

1. 下载本项目 [ZIP 文件](https://github.com/ScientificInternet/AI-Xray/archive/refs/heads/main.zip)
2. Cloudflare Dashboard → Workers & Pages → 创建 → Pages → 上传资产
3. 上传 ZIP → 部署 → 添加 UUID 环境变量 → 重新部署

### 第二步：获取节点

浏览器访问：

```
https://你的项目.pages.dev/你的UUID
```

页面会显示：
- VLESS 节点链接（直接复制到客户端）
- 订阅地址（支持 Clash / V2rayN / Shadowrocket 等）
- 二维码（手机扫码导入）

### 第三步：优选 CF IP（可选）

默认使用 CF 官方 Anycast IP，开箱即用。如需进一步提速，AI 会自动扫描美、亚、欧三区域的 CF IP，选出延迟最低的节点推送到你的订阅。

---

## 专业模式安装流程

### 第一步：环境检测

脚本自动完成：
- 系统环境检测（OS / 架构 / 内核）
- VPS 综合测试（三网回程路由、线路质量）
- IP 解锁检测（ChatGPT / Claude / TikTok / Netflix）
- 如果 IP 为广播 IP 或不解锁关键平台，脚本会提示建议更换 VPS

### 第二步：部署 Xray

- 下载安装最新版 Xray-core
- 根据 VPS 地理位置自动选择最佳 dest（伪装目标站点）
- 生成 VLESS + Reality + Vision 配置
- 开启 BBR 加速
- 注册 systemd 服务

### 第三步：白名单 & TOS

默认白名单仅允许访问跨境电商平台：

| 平台 | 域名 |
|------|------|
| TikTok Business | business.tiktok.com |
| Amazon Seller | sellercentral.amazon.com |
| Google Ads | ads.google.com |
| Meta Business | business.facebook.com |
| Shopify | admin.shopify.com |

用户可自行修改白名单。删除任何条目时会弹出 TOS 提示，确认后法律责任由用户自行承担。

### 第四步：AI 守卫启动

安装完成后，AI 守卫常驻进程自动启动：

```
[AI-Xray] 守卫已启动
[AI-Xray] 当前 dest: addons.mozilla.org
[AI-Xray] 监测中...延迟 142ms / 丢包 0% / RST 0
```

### 第五步：获取订阅链接

脚本自动输出：
- VLESS 链接（可直接导入客户端）
- 订阅地址（支持自动更新配置）
- 二维码（手机扫码导入）

---

## AI 守卫

v0.1 使用阈值规则引擎做决策，未来版本将升级为训练模型驱动。当前能力：

### 监测

每分钟检测网络健康指标：
- 延迟变化（与基线对比）
- 丢包率
- TCP RST 异常计数

### 换脸

指标超阈值时触发：修改 dest / SNI / shortId，重启 Xray。**注意：重启会导致当前连接中断，客户端需重新拉取订阅获取新配置（默认每小时自动更新）。** 只在连接已经出问题时才触发，所以影响有限。

### 记录

换脸结果写入本地 SQLite，用于未来模型训练。`ai-xray export` 可导出匿名训练数据。

### 流量整形

新安装节点的最大并发连接数从 20 逐步增长到 200（7 天周期），避免流量突增引起注意。

---

## dest 智能选择

Reality 协议的 dest（伪装目标）选择直接影响存活时间。

AI-Xray 不是随机选，而是根据：
- VPS 地理位置（美国 VPS 选美国大站，不选日本站）
- 目标站点 TLS 1.3 支持状态
- 目标站点全球 CDN 分布密度
- 社区反馈的 dest 存活数据

预置 dest 池包括但不限于：
`addons.mozilla.org` `www.microsoft.com` `www.apple.com` `www.cloudflare.com` `www.samsung.com` 等

---

## 管理命令

```bash
ai-xray              # 打开管理菜单
ai-xray status       # 查看运行状态
ai-xray log          # 查看 AI 守卫日志
ai-xray morph        # 手动触发换脸
ai-xray dest         # 查看/管理 dest 池
ai-xray whitelist    # 查看/编辑白名单
ai-xray sub          # 显示订阅链接和二维码
ai-xray update       # 更新 AI-Xray
ai-xray uninstall    # 卸载
```

---

## 客户端

AI-Xray 生成的订阅链接兼容所有主流客户端：

| 平台 | 推荐客户端 |
|------|-----------|
| Windows | v2rayN, Clash Verge Rev |
| macOS | Clash Verge Rev, V2rayU |
| Android | v2rayNG, ClashMeta |
| iOS | Shadowrocket, Stash |
| OpenWrt | OpenClash, Passwall2 |

### OpenWrt AI Plugin

路由器级别一装，家里所有设备全走 AI 智能线路。

```bash
# SSH into your OpenWrt router, then:
sh <(curl -fsSL https://raw.githubusercontent.com/ScientificInternet/AI-Xray/main/openwrt/install-openwrt.sh) "你的订阅链接"
```

插件自动完成：
- 安装 mihomo 核心
- 解析订阅链接（支持 VLESS / VMess / SS / Trojan）
- 生成最优配置（DNS / 分流 / 策略组）
- 启动 AI Router 守护进程
- 配置透明代理（所有 LAN 设备自动走代理）
- 实时监测所有节点健康，预判死亡提前切换
- 30 秒检测一次，2x 基线延迟触发切换，120 秒切换冷却

---

## 协议选型

| 协议 | 抗 GFW | 速度 | 需要域名 | 本项目 |
|------|-------|------|---------|--------|
| VLESS+Reality+Vision | 最强 | 快 | 不需要 | 专业模式 |
| VLESS+WS+TLS (CF) | 中等 | 一般 | 不需要 | 免费模式 |
| Hysteria2 | 中等 | 最快 | 不需要 | 暂不支持 |
| VMess | 弱（已被破解） | 快 | 需要 | 不支持 |
| Trojan | 中等 | 快 | 需要 | 暂不支持 |

专业模式锁定 VLESS + Reality + Vision，一台服务器只跑一个协议。

---

## 与其他脚本的区别

| 维度 | mack-a 八合一 | edgetunnel | BPB Panel | AI-Xray |
|------|-------------|-----------|-----------|---------|
| 被封后 | 手动重装 | 手动换 | 手动调 | AI 自动换脸 |
| IP 检测 | 无 | 无 | 手动扫描 | 安装时自动检测 |
| dest 选择 | 手动输入 | 不适用 | 不适用 | 根据地理位置自动选 |
| 流量整形 | 无 | 无 | 无 | 自动控制行为模式 |
| 越用越聪明 | 否 | 否 | 否 | 是 |
| 免费模式 | 不支持 | 支持 | 支持 | 支持 |
| VPS 模式 | 支持 | 不支持 | 不支持 | 支持 |
| 白名单 | 无 | 无 | 有路由规则 | 默认跨境平台 |

---

## 数据与隐私

- 客户端（OpenWrt 插件）**零数据上传**
- 服务端守卫的所有决策在本地完成
- 换脸日志仅存本地 SQLite，不外传
- `ai-xray export` 可导出匿名数据供社区模型训练（手动操作，非自动）

---

## 系统要求

专业模式：
- Debian 10+ / Ubuntu 20+ / CentOS 7+
- 最低 256MB 内存
- root 权限

免费模式：
- 一个 Cloudflare 免费账号
- 一个 GitHub 账号（Pages 部署用）

---

## 免责声明

1. 本项目仅供跨境电商从业者合法访问海外商业平台使用
2. 默认白名单仅包含跨境电商平台，产品定位为跨境网络加速器
3. 用户自行修改白名单后的所有行为由用户自行承担法律责任
4. 本项目不提供任何形式的翻墙服务
5. 使用前请遵守当地法律法规

---

## License

MIT
