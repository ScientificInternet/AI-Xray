# AI-Xray 开发日志

## 2026-05-06 Phase 1: 服务端脚本重写

### 当前代码问题分析

**install.sh (928行)：**
1. ✅ 基础框架可用（依赖安装、系统检测、Xray 安装）
2. ❌ AI Guard 是假的：
   - 假 M-Lab NDT7（已删除）
   - 假热重载（注释说 SIGHUP 但代码是 restart）
   - 固定阈值规则引擎（latency>500ms / loss>10% / rst>5）
   - restart 会断开所有连接
3. ❌ 缺少工具链集成：
   - NTrace-core（路由追踪）
   - RegionRestrictionCheck（流媒体解锁）
   - Unlock-Check（跨境平台检测）
4. ✅ 白名单路由已修复（jq 重写 routing.rules）
5. ✅ TOS 双重确认已有

### 对比 mack-a/v2ray-agent (10079行)

**学到的最佳实践：**
1. **Reality dest 选择**：
   - 提供 40+ 预设 dest 列表（addons.mozilla.org, www.cisco.com, www.samsung.com 等）
   - 用户可自定义 dest:port
   - 保存历史 key 供重装时复用
   
2. **配置管理**：
   - 多 JSON 文件拆分（07_VLESS_vision_reality_inbounds.json）
   - 保存 reality_key 到独立文件
   - 读取上次安装配置避免重复输入

3. **shortIds 数组**：
   - 使用 `["", "6ba85179e30d4fc2"]` 两个值
   - 空字符串 + 随机 hex，增加兼容性

4. **XHTTP 支持**：
   - Reality + XHTTP（上下行分离）
   - 自定义 path

**我们的差异化：**
- mack-a 是八合一（Xray/Tuic/hysteria2/sing-box），我们只做 Xray Reality
- mack-a 是静态配置，我们做 AI 驱动的动态换脸
- mack-a 10k 行太重，我们保持轻量（<1500 行）

### 改进计划

**Phase 1.1: 重写 AI Guard**
- [ ] 去掉假 M-Lab
- [ ] 修正注释（restart 不是热重载）
- [ ] 研究 Xray gRPC API（运行时改配置）
- [ ] 改进 dest 选择（参考 mack-a 的 40+ 列表）
- [ ] shortIds 数组（空字符串 + hex）
- [ ] 保存 reality_key 到独立文件

**Phase 1.2: 集成工具链**
- [ ] NTrace-core（路由追踪）
- [ ] RegionRestrictionCheck（流媒体解锁）
- [ ] Unlock-Check（跨境平台检测）

**Phase 1.3: 优化配置管理**
- [ ] 保存历史配置供重装复用
- [ ] 多 dest 池按地区分组（US/EU/AP）

---

## 下一步

开始重写 AI Guard，先解决核心问题。
