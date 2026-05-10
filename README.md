# AI-Xray

跨境电商 & AI 生产力加速器

为跨境从业者打造的网络加速工具。出厂预置 Google Ads、Meta、TikTok、
ChatGPT、Claude 等平台白名单，一行命令部署，开箱即用。

---

## 一行安装 / One-line Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ScientificInternet/AI-Xray/v2.0/install.sh)
```

---

## 功能 / Features

- **VMESS + WS + TLS** — 过CDN，极其稳定 / CDN-compatible, extremely stable
- **AI伪装站** — 三层fallback自动生成 / AI-generated site with 3-layer fallback
- **白名单保护** — 出厂锁定跨境和AI平台，不是通用代理 / Whitelist-gated by default
- **VPS质量检测** — 安装前自动检查 / Pre-install VPS quality check
- **一行命令** — 全自动安装 / Fully automated installation
- **一个菜单** — `ai-xray` 管理一切 / One command to manage everything

---

## 为什么选AI-Xray / Why AI-Xray

**出厂即合规。** 默认白名单锁定跨境电商和AI生产力平台，
不是通用代理。你的服务器就是一台专用的工作加速器。

---

## 安装流程 / Installation Flow

1. 输入域名（必须已解析到服务器）/ Enter your domain (must resolve to the server)
2. 选择伪装站类型（默认AI协议文档站）/ Choose camouflage site type
3. 等待全自动完成 / Wait for auto-completion

---

## VPS要求 / VPS Requirements

| 项目 | 最低要求 |
|------|----------|
| 内存 | 512MB |
| 硬盘 | 10GB |
| 系统 | CentOS 7/8/9, Debian 10/11/12, Ubuntu 18.04/20.04/22.04/24.04 |
| 架构 | x86_64 |
| 域名 | 必须已解析到服务器 |

---

## 管理命令 / Management

安装完成后输入 `ai-xray` 进入管理菜单：

| 选项 | 功能 |
|------|------|
| 1 | 查看连接信息 / View connection info |
| 2 | 重新生成伪装站 / Regenerate camouflage site |
| 3 | 更新Xray内核 / Update Xray core |
| 4 | 重启服务 / Restart services |
| 5 | 查看日志 / View logs |
| 6 | 查看状态 / Check status |
| 7 | 白名单管理 — 查看/添加/删除/恢复默认 |
| 8 | 卸载 / Uninstall |

---

## 白名单管理 / Whitelist

出厂默认白名单：

```
google.com    facebook.com   tiktok.com
x.com         pinterest.com  openai.com
claude.ai
```

- **添加**：即时生效，不弹TOS
- **删除**：弹TOS全文，须输入 `YES` 确认
- **全部删除**：解锁全部流量，须输入 `YES` 确认
- **恢复默认**：一键回到出厂状态

---

## 许可 / License

MIT
