# AI-Xray

> 跨境电商加速器 v2.0 · Cross-border E-commerce Accelerator
>
> VMESS + WebSocket + TLS + CDN · AI-generated camouflage site

---

## 一行安装 / One-line Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ScientificInternet/AI-Xray/main/install.sh)
```

---

## 功能 / Features

- **VMESS + WS + TLS** — 过CDN，极其稳定 / CDN-compatible, extremely stable
- **AI伪装站** — 三层fallback自动生成 / AI-generated site with 3-layer fallback
- **VPS质量检测** — 安装前自动检查 / Pre-install VPS quality check
- **一行命令** — 全自动安装 / Fully automated installation
- **一个菜单** — `ai-xray` 管理一切 / One command to manage everything

---

## 安装流程 / Installation Flow

1. 输入域名（必须已解析到服务器）/ Enter your domain (must resolve to the server)
2. 选择伪装站类型（默认AI协议文档站）/ Choose camouflage site type
3. 全自动：安装依赖 → Xray → 证书 → 配置 → 伪装站 → BBR → 启动
4. 复制VMess链接到客户端 / Copy VMess link to client

---

## 客户端教程 / Client Tutorial

👉 **[ssr.dedyn.io](https://ssr.dedyn.io)**

推荐客户端 / Recommended clients:
- **iOS**: Shadowrocket
- **Android**: v2rayNG
- **Windows**: v2rayN
- **macOS**: V2rayU

---

## Cloudflare CDN（推荐）

1. 域名 DNS 管理中开启橙色云朵 (Proxied)
2. SSL/TLS 模式选择 **Full (strict)**
3. 开启后 VPS IP 被隐藏，极其稳定

---

## 管理命令 / Management

```bash
ai-xray
```

| 选项 | 说明 |
|---|---|
| 1 | 查看连接信息 / View connection info |
| 2 | 重新生成伪装站 / Regenerate camouflage site |
| 3 | 更新Xray内核 / Update Xray core |
| 4 | 重启服务 / Restart services |
| 5 | 查看日志 / View logs |
| 6 | 查看状态 / Check status |
| 7 | 卸载 / Uninstall |

---

## 推荐VPS / Recommended VPS

| 商家 | 链接 |
|---|---|
| 搬瓦工 DC8ZNET CN2 GIA | [bwh81.net](https://bwh81.net/aff.php?aff=20308) |
| DMIT | [dmit.io](https://www.dmit.io/aff.php?aff=3138) |
| Vultr | [vultr.com](https://www.vultr.com/?ref=9631926-9J) |

---

## 免费版 / Free Edition

不需要VPS？试试纯免费版 → [AI-Xray-Free](https://github.com/ScientificInternet/AI-Xray-Free)

---

## 致谢 / Acknowledgments

Built on the shoulders of giants:
- [Xray-core](https://github.com/XTLS/Xray-core)
- [acme.sh](https://github.com/acmesh-official/acme.sh)
- [Nginx](https://nginx.org/)
- [Let's Encrypt](https://letsencrypt.org/)

---

## 许可证 / License

MIT © ScientificInternet
