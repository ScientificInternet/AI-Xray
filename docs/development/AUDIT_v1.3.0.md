# AI-Xray v1.3.0 安全审计报告

**审计时间**: 2026-05-07  
**审计版本**: v1.3.0 (commit: e5848ee)  
**对比基线**: v1.2.1  
**审计人**: 龙虾工厂

---

## 执行摘要

**总体评级**: ⚠️ **中风险 - 不建议生产使用**

**关键发现**:
- 2 个 P0 致命问题
- 1 个 P1 工程问题
- 1 个 P1 供应链残留

**建议**: 立即修复 P0 问题后发布 v1.3.1

---

## P0 致命问题

### P0-1: 无限递归导致堆栈溢出

**文件**: `install-simple.sh` 第 23 行, `install-full.sh` 第 24 行

**问题**:
```bash
error_exit() {
    local message="$1"
    echo ""
    echo -e "${red}========================================${none}"
    echo -e "${red}Installation Failed${none}"
    echo -e "${red}========================================${none}"
    echo ""
    error_exit "${message}"  # ← 递归调用自己！
    echo ""
    ...
    exit 1
}
```

**影响**:
- 任何安装失败都会触发无限递归
- 堆栈溢出，进程崩溃
- 用户看不到错误信息
- 无法正常退出

**正确实现** (install.sh 第 24 行):
```bash
echo -e "${red}Error: ${message}${none}"
```

**修复方案**:
```bash
# install-simple.sh 第 23 行
# install-full.sh 第 24 行
- error_exit "${message}"
+ echo -e "${red}Error: ${message}${none}"
```

**严重程度**: 🔴 **CRITICAL**  
**影响范围**: 所有使用 install-simple.sh 或 install-full.sh 的用户  
**复现概率**: 100% (任何安装失败)

---

### P0-2: 版本号混乱

**文件**: `README.md`

**问题**:
```markdown
第 49 行: v1.3.0/install.sh          ✅ 正确
第 94 行: v1.2.1/install-simple.sh   ❌ 错误
第 161 行: v1.2.1/whitelist-manager.sh ❌ 错误
```

**影响**:
- 用户以为安装 v1.3.0，实际部分组件是 v1.2.1
- Release 内容与安装入口不一致
- 可能导致功能缺失或不兼容

**修复方案**:
```bash
# README.md 第 94 行
- bash <(curl -fsSL https://raw.githubusercontent.com/ScientificInternet/AI-Xray/v1.2.1/install-simple.sh)
+ bash <(curl -fsSL https://raw.githubusercontent.com/ScientificInternet/AI-Xray/v1.3.0/install-simple.sh)

# README.md 第 161 行
- bash <(curl -fsSL https://raw.githubusercontent.com/ScientificInternet/AI-Xray/v1.2.1/whitelist-manager.sh)
+ bash <(curl -fsSL https://raw.githubusercontent.com/ScientificInternet/AI-Xray/v1.3.0/whitelist-manager.sh)
```

**严重程度**: 🔴 **CRITICAL**  
**影响范围**: 所有用户  
**复现概率**: 100%

---

## P1 高风险问题

### P1-1: 供应链残留 - RegionRestrictionCheck

**文件**: `install.sh` 第 205 行, `install-full.sh` 第 621 行

**问题**:
```bash
curl -fsSL https://raw.githubusercontent.com/lmc999/RegionRestrictionCheck/main/check.sh | bash -s -- ...
```

**风险**:
- 拉取 `main` 分支（可变内容）
- 直接 pipe 到 bash
- 无 commit hash pin
- 无 sha256 校验

**对比**: Xray 安装已固定
```bash
XRAY_INSTALL_COMMIT="e741a4f5"
XRAY_INSTALL_SHA256="7f70c95f6b418da8b4f4883343d602964915e28748993870fd554383afdbe555"
```

**修复方案**:
1. Pin 到具体 commit
2. 下载后校验 sha256
3. 或者内置检测脚本

**严重程度**: 🟡 **HIGH**  
**影响范围**: 所有使用 VPS 质量检测的用户  
**复现概率**: 低（需要上游投毒）

---

### P1-2: 仓库污染

**问题**: 根目录堆积 7 个测试/开发文件

```
CHECKLIST.md
WORK_LOG.md
SUCCESS_REPORT.md
TEST_REPORT.md
TEST_RESULTS.md
MULTI_SYSTEM_TEST.md
MULTI_SYSTEM_TEST_REPORT.md
```

**影响**:
- 用户看到会觉得项目还在 alpha 阶段
- 降低项目可信度
- 混淆主要文档

**修复方案**:
```bash
mkdir -p docs/development
mv *_REPORT.md *_LOG.md CHECKLIST.md docs/development/
```

**严重程度**: 🟡 **MEDIUM**  
**影响范围**: 项目形象  
**复现概率**: 100%

---

## P1-3: 多 README 混乱

**问题**: 3 个 README + 3 个 install 脚本

```
README.md           (主文档)
README-FINAL.md     (?)
README-SIMPLE.md    (?)

install.sh          (713 行)
install-simple.sh   (953 行)
install-full.sh     (3806 行)
```

**影响**:
- 用户不知道该看哪个
- 用户不知道该跑哪个
- 维护成本高（3 份文档要同步）

**建议**:
1. 只保留 `README.md`
2. 删除 `README-FINAL.md` 和 `README-SIMPLE.md`
3. 或者移到 `docs/` 并在主 README 说明用途

**严重程度**: 🟡 **MEDIUM**  
**影响范围**: 用户体验  
**复现概率**: 100%

---

## ✅ 保持正确的部分

### 1. Xray 供应链固定 ✅
```bash
XRAY_INSTALL_COMMIT="e741a4f5"
XRAY_INSTALL_SHA256="7f70c95f6b418da8b4f4883343d602964915e28748993870fd554383afdbe555"
```

### 2. jq 注入修复 ✅
```bash
jq --arg domain "$domain" ...
```

### 3. 配置路径统一 ✅
```bash
CONFIG_FILE="/usr/local/etc/xray/config.json"
```

---

## 修复优先级

| 优先级 | 问题 | 修复时间 | 阻塞发版 |
|--------|------|----------|----------|
| P0 | 无限递归 | 5 分钟 | ✅ 是 |
| P0 | 版本号混乱 | 2 分钟 | ✅ 是 |
| P1 | 供应链残留 | 30 分钟 | ⚠️ 建议 |
| P1 | 仓库污染 | 5 分钟 | ❌ 否 |
| P1 | 多 README | 10 分钟 | ❌ 否 |

---

## 建议行动

### 立即修复 (v1.3.1)
1. 修复 `install-simple.sh` 和 `install-full.sh` 的 `error_exit` 递归
2. 统一所有 README 的版本号到 v1.3.1
3. 固定 RegionRestrictionCheck 到具体 commit

### 后续清理 (v1.3.2)
4. 清理根目录测试文件
5. 合并或删除多余 README

---

## 测试建议

### 回归测试
```bash
# 测试 error_exit 是否正常工作
bash install-simple.sh  # 故意触发错误
# 预期：显示错误信息并退出，不应堆栈溢出

# 测试版本一致性
grep -r "v1\.[0-9]\.[0-9]" README*.md
# 预期：所有版本号都是 v1.3.1
```

### 供应链测试
```bash
# 验证 Xray 安装脚本 sha256
curl -fsSL https://raw.githubusercontent.com/XTLS/Xray-install/e741a4f5/install-release.sh | sha256sum
# 预期：7f70c95f6b418da8b4f4883343d602964915e28748993870fd554383afdbe555
```

---

## 结论

v1.3.0 引入了 **2 个 P0 致命 bug**，不建议生产使用。

**必须立即发布 v1.3.1 修复 P0 问题。**

P1 问题可以在后续版本逐步清理。
