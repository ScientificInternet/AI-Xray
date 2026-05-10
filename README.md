# AI-Xray

跨境电商 & AI 生产力加速器

为跨境从业者解决海外平台访问慢、不稳定的问题。出厂预置 Google Ads、Meta、TikTok、ChatGPT、Claude 等业务平台白名单，一行命令部署，开箱即用。

## 解决什么问题

跨境电商从业者每天要用 Google Ads 投广告、Meta Business 管主页、TikTok Ads 跑素材、ChatGPT/Claude 写文案。这些平台从国内访问慢、掉线、打不开，严重影响工作效率。

AI-Xray 在你的海外服务器上部署一条加速通道，专门加速这些业务平台。默认只加速白名单内的平台，不是通用网络工具。

## 一行安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ScientificInternet/AI-Xray/main/install.sh)
```

输入域名 → 选站点类型 → 等两分钟 → 复制连接信息到客户端 → 开始工作。

## 默认业务白名单

安装完成后，仅以下业务平台可通过加速通道访问：

| 平台 | 域名 | 业务场景 |
|------|------|----------|
| Google | google.com | Ads投放、Analytics分析、Search Console、Merchant Center |
| Meta | facebook.com | Business Suite、广告投放、主页管理 |
| TikTok | tiktok.com | Ads Manager、店铺管理、素材投放 |
| X (Twitter) | x.com | 广告投放、社媒运营 |
| Pinterest | pinterest.com | 广告投放、选品调研 |
| OpenAI | openai.com | ChatGPT |
| Anthropic | claude.ai | Claude |

白名单外的流量不经过加速通道。可通过管理菜单添加其他业务平台。

## 特性

**业务专用。** 默认白名单锁定跨境电商和AI生产力平台。这是一台专用的工作加速器，不是通用网络工具。

**协议稳定。** VMESS + WebSocket + TLS，经过Cloudflare CDN实战验证的组合，稳定性优先。

**AI站点防护。** 每台服务器自动生成独立的前端页面，三层fallback机制保证100%生成成功。

**全平台兼容。** CentOS 7/8/Stream 9、Debian 10/11/12、Ubuntu 18.04~24.04，10个发行版测试全绿。

## 系统兼容性

| 发行版 | 版本 | 状态 | 备注 |
|--------|------|------|------|
| CentOS | 7 | ✅ | BBR自动跳过（内核3.10） |
| CentOS | 8 | ✅ | |
| CentOS | Stream 9 | ✅ | |
| Debian | 10 | ✅ | |
| Debian | 11 | ✅ | |
| Debian | 12 | ✅ | |
| Ubuntu | 18.04 | ✅ | |
| Ubuntu | 20.04 | ✅ | |
| Ubuntu | 22.04 | ✅ | |
| Ubuntu | 24.04 | ✅ | |

## 客户端

安装完成后，将连接信息导入客户端即可使用：

| 平台 | 推荐客户端 |
|------|------------|
| iOS | Shadowrocket |
| Android | v2rayNG |
| Windows | v2rayN |
| macOS | V2rayU |

客户端配置教程：**[ssr.dedyn.io](https://ssr.dedyn.io)**

## Cloudflare CDN（推荐）

域名DNS管理中开启橙色云朵（Proxied），SSL/TLS模式选Full (strict)。通过Cloudflare全球网络加速业务访问，提升稳定性。

## 管理

```bash
ai-xray
```

| 选项 | 功能 |
|------|------|
| 1 | 查看连接信息 |
| 2 | 重新生成站点 |
| 3 | 更新Xray内核 |
| 4 | 重启服务 |
| 5 | 查看日志 |
| 6 | 查看状态 |
| 7 | 白名单管理 |
| 8 | 卸载 |

## 推荐VPS

| 商家 | 特点 | 链接 |
|------|------|------|
| 搬瓦工 DC8ZNET | CN2 GIA，中国直连最快 | [bwh81.net](https://bwh81.net/aff.php?aff=20308) |
| DMIT | 香港/洛杉矶，大带宽 | [dmit.io](https://www.dmit.io/aff.php?aff=3138) |
| Vultr | 按小时计费，随开随关 | [vultr.com](https://www.vultr.com/?ref=9631926-9J) |

## 免费版

不需要自己的服务器？试试免费版 → [AI-Xray-Free](https://github.com/ScientificInternet/AI-Xray-Free)

## 免责声明

AI-Xray 是为跨境电商从业者设计的业务平台加速工具。默认配置仅加速预置白名单内的业务平台。用户对自行修改白名单后的所有网络行为承担全部法律责任。开发者不对任何超出原始业务加速用途的使用承担责任。

## 致谢

基于 [Xray-core](https://github.com/XTLS/Xray-core) / [acme.sh](https://github.com/acmesh-official/acme.sh) / [Nginx](https://nginx.org/) / [Let's Encrypt](https://letsencrypt.org/) 构建。

## 许可证

MIT © ScientificInternet
