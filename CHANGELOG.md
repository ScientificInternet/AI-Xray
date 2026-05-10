# Changelog

## v2.1.0 (2026-05-08)

### 安全加固（17项审计修复）
- Xray-install: pin commit + SHA256 校验
- acme.sh: pin 版本 + SHA256 校验，下载脚本不管道执行
- 依赖安装: 逐包安装，失败即退出，保留 stderr
- 端口检测: ss -ntlp 探测 + sleep 2 + shuf 随机端口循环验证空闲
- BBR: 写入 /etc/sysctl.d/99-bbr.conf drop-in，不再直接修改 sysctl.conf
- 卸载: 读取 info.json managedPaths，仅删除脚本创建的文件
- 证书续期: --reloadcmd 自动 reload nginx
- 新增 test_configs: nginx -t + xray run -test 部署前验证
- IP 获取: 多源 fallback
- Worker 响应校验
- tar 解压错误处理
- nginx repo: https + gpgcheck
- preflight 预检 + 配置备份机制
- 全局防火墙/SELinux 不关闭（仅处理阻止通信的规则）

### 白名单 + TOS
- 出厂默认 7 个跨境电商/AI 域名白名单
- Xray routing 白名单外流量全部 block
- TOS.txt 条款，删除域名需阅读全文并输入 YES 确认
- 管理菜单新增「白名单管理」选项（添加/删除/全部删除/恢复默认）

### 兼容性修复
- CentOS 7: BBR 检测从 grep bbr 改为 tcp_available_congestion_control
- CentOS 8: 补充 tar 依赖
- set -e 下 ping / grep / curl / systemctl 容错处理
- nginx 配置统一使用 conf.d，避免 sites-enabled 双重加载
- VMess 链接 add 字段从 IP 改为域名
- BBR 重复写入检测

### 文字修正
- 「伪装站」→「站点」
- README 定位重写为「跨境电商 & AI 生产力加速器」，移除敏感词
- CHANGELOG / NOTICE / install.sh 中 camouflage 术语替换

### 已验证系统
- CentOS 7 / 8 / Stream 9
- Debian 10 / 11 / 12
- Ubuntu 18.04 / 20.04 / 22.04 / 24.04

## v2.0.0 (2026-05-08)

### Rewritten from scratch
- Single `install.sh` replacing all previous scripts
- VMESS + WS + TLS only (removed Reality, VLESS, Trojan, XTLS, KCP, gRPC)
- AI-powered site generation with 3-layer fallback:
  - Level 1: Real-time AI generation via Cloudflare Worker
  - Level 2: Local rendering from open-source template pool
  - Level 3: Temporary redirect
- Simplified VPS quality check (3 tests instead of 8)
- Single-file management command `ai-xray`
- Clean repo structure: 7 files total

### Removed
- All multi-protocol support
- `install-simple.sh`, `install-full.sh`
- Legacy README variants
- `_worker.js`, `wrangler.toml`
- All test reports and work logs

### Reference
- `docs/reference/xray-v1-reference.sh` retained as historical reference
