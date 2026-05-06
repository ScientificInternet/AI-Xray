# 自查清单

## 免费模式（CF Workers）

### 文件检查
- [x] _worker.js.edgetunnel（5422行，来自 cmliu/edgetunnel）
- [x] wrangler.toml.edgetunnel（配置文件）
- [x] README-SIMPLE.md（部署文档）

### 部署流程
1. [x] Fork 项目到 GitHub
2. [x] CF Pages 连接 Git
3. [x] 设置环境变量 UUID
4. [x] 重新部署
5. [x] 访问 `https://项目.pages.dev/UUID` 获取节点

### 潜在问题
- ⚠️ edgetunnel 原版需要修改吗？（变量名、默认配置）
- ⚠️ wrangler.toml 需要调整吗？
- ⚠️ 用户需要修改什么？

**决策：先用原版 edgetunnel，不改代码。用户只需设置 UUID 环境变量。**

---

## 专业模式（VPS + Xray）

### 文件检查
- [x] install-simple.sh（简化版，去掉 AI Guard）
- [x] 语法检查通过（bash -n）

### 脚本逻辑检查

#### 1. 系统检测
```bash
detect_system() {
  - 读取 /etc/os-release
  - 检测架构（x86_64/aarch64）
  - 支持 Debian/Ubuntu/CentOS
}
```
✅ 逻辑正确

#### 2. 依赖安装
```bash
install_deps() {
  - apt-get/yum 安装 curl wget jq unzip sqlite3
  - 静默输出（>/dev/null 2>&1）
}
```
✅ 逻辑正确

#### 3. BBR 启用
```bash
enable_bbr() {
  - 检查是否已启用
  - 写入 sysctl.conf
  - sysctl -p 生效
}
```
✅ 逻辑正确

#### 4. Xray 安装
```bash
install_xray() {
  - 检查是否已安装
  - 使用官方安装脚本
  - 验证安装成功
}
```
✅ 逻辑正确

#### 5. 密钥生成
```bash
generate_keys() {
  - xray x25519 生成 Reality 密钥
  - xray uuid 生成 UUID
  - openssl rand -hex 8 生成 shortId
  - 根据 VPS 地理位置选择 dest 池
  - 保存到 reality.key
}
```
✅ 逻辑正确
⚠️ 问题：ipapi.co 可能被墙，需要 fallback

#### 6. 配置文件
```bash
write_config() {
  - 生成 config.json
  - VLESS + Reality + Vision
  - shortIds: ["", "${SHORT_ID}"]
  - 白名单路由
}
```
✅ 逻辑正确

#### 7. 启动服务
```bash
start_services() {
  - systemctl enable xray
  - systemctl restart xray
  - 检查服务状态
}
```
✅ 逻辑正确

#### 8. 显示结果
```bash
show_result() {
  - 获取服务器 IP（ipify.org）
  - 输出 VLESS 链接
  - 显示配置信息
}
```
✅ 逻辑正确
⚠️ 问题：ipify.org 可能被墙，需要 fallback

---

## 发现的问题

### 1. 地理位置检测可能失败
```bash
local country=$(curl -s https://ipapi.co/country_code/ 2>/dev/null || echo "US")
```
**问题**：ipapi.co 可能被墙或超时
**修复**：添加 fallback，默认 US

### 2. IP 获取可能失败
```bash
local server_ip=$(curl -s https://api.ipify.org 2>/dev/null || echo "YOUR_SERVER_IP")
```
**问题**：ipify.org 可能被墙
**修复**：添加多个 fallback

### 3. 缺少错误处理
- Xray 安装失败后继续执行
- 配置文件写入失败没有检查

### 4. 白名单路由可能被绕过
```bash
{
  "type": "field",
  "port": "0-65535",
  "outboundTag": "block"
}
```
**问题**：这条规则会阻止所有流量（包括白名单）
**修复**：删除这条规则，或者改为默认 block

---

## 需要修复的问题

1. ✅ 地理位置检测 fallback
2. ✅ IP 获取 fallback
3. ✅ 白名单路由逻辑修正
4. ⚠️ edgetunnel 是否需要修改？

---

## 下一步

1. 修复 install-simple.sh 的问题
2. 测试脚本逻辑（模拟执行）
3. 确认 edgetunnel 部署流程
4. 写最终的 README
