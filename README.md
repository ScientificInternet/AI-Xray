# AI-Xray

跨境电商加速器 · Cross-border E-commerce Accelerator

VMESS + WebSocket + TLS + Cloudflare CDN + AI伪装站 · 一行命令，全自动部署

## 一行安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ScientificInternet/AI-Xray/main/install.sh)
```

输入域名 → 选伪装站类型 → 等两分钟 → 复制VMess链接到客户端 → 完事。

## 为什么选AI-Xray

**只做一件事，做到极致。** 不搞VLESS/Trojan/Reality/gRPC/KCP多协议大杂烩。VMESS + WS + TLS是唯一经过CDN实战验证的稳定组合，没有之一。

**AI生成专属伪装站。** 每台服务器的伪装站都不一样，三层fallback保证100%生成成功。你的服务器看起来就是一个正常的技术文档网站。

**10个Linux发行版测试全绿。** 不是"理论上支持"，是每一个都跑过完整安装流程。

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

## 安装完成后

安装脚本输出VMess链接，复制到客户端即可使用。

推荐客户端：

| 平台 | 客户端 |
|------|--------|
| iOS | Shadowrocket |
| Android | v2rayNG |
| Windows | v2rayN |
| macOS | V2rayU |

客户端配置教程：**[ssr.dedyn.io](https://ssr.dedyn.io)**

## Cloudflare CDN（强烈推荐）

域名DNS管理中开启橙色云朵（Proxied），SSL/TLS模式选Full (strict)。开启后VPS真实IP被Cloudflare隐藏，极其稳定。

## 管理

```bash
ai-xray
```

查看连接信息 / 重新生成伪装站 / 更新Xray内核 / 重启服务 / 查看日志 / 查看状态 / 卸载。一个命令管一切。

## 推荐VPS

| 商家 | 特点 | 链接 |
|------|------|------|
| 搬瓦工 DC8ZNET | CN2 GIA，中国直连最快 | [bwh81.net](https://bwh81.net/aff.php?aff=20308) |
| DMIT | 香港/洛杉矶，大带宽 | [dmit.io](https://www.dmit.io/aff.php?aff=3138) |
| Vultr | 按小时计费，随开随关 | [vultr.com](https://www.vultr.com/?ref=9631926-9J) |

## 免费版

不想买VPS？试试纯免费版 → [AI-Xray-Free](https://github.com/ScientificInternet/AI-Xray-Free)

## 致谢

基于 [Xray-core](https://github.com/XTLS/Xray-core) / [acme.sh](https://github.com/acmesh-official/acme.sh) / [Nginx](https://nginx.org/) / [Let's Encrypt](https://letsencrypt.org/) 构建。

## 许可证

MIT © ScientificInternet
