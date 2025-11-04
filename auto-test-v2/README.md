# Auto-Test V2 - 目标导向的自动化测试脚本生成器

## 🎯 核心理念

**从"模拟人类操作"到"目标导向测试"**

- ❌ **旧方案**: 逐步模拟人类操作（打开 Explorer、点击菜单等）
- ✅ **新方案**: 理解测试目标，用 PowerShell 直接达成效果

## ✨ 主要特点

1. **人类步骤作为背景知识** - CSV 中的 steps 用于理解测试意图，而非逐步模拟
2. **完全静默操作** - 所有操作无 UI 弹窗（使用 `/qn` 而非 `/qn+`）
3. **脚本验证** - 通过 PowerShell 检查结果（注册表、服务、文件），不依赖视觉
4. **单会话执行** - 所有操作在一个管理员 PowerShell 会话中完成
5. **AI 理解语义** - AI 分析人类步骤，生成目标导向的测试脚本

## 📁 项目结构

```
auto-test-v2/
├── run.py              # 主入口程序
├── config/
│   └── prompts.py      # AI 提示模板（目标导向设计）
├── core/
│   ├── csv_parser.py   # CSV → JSON 转换
│   ├── model_client.py # Azure OpenAI 客户端
│   └── test_generator.py  # 测试脚本生成器
├── input/              # 输入 CSV/JSON 文件
├── output/             # 生成的 PowerShell 测试脚本
└── templates/          # 脚本模板（可选）
```

## 🚀 使用方法

### 方法 1: 从 CSV 生成

```powershell
python run.py --csv input/case1test.csv
```

CSV 格式:
```csv
Step,Action,Expected
1,Apply to all devices.,
2,Press "Win + E" keys and go to C:\VMShare,
3,Open PowerShell as administrator,
4,Run: msiexec /i cmdextension.msi /qn+,Installation completes with success dialog
5,Open Control Panel and verify,Microsoft Cloud Managed Desktop Extension is installed
...
```

### 方法 2: 从 JSON 生成

```powershell
python run.py --json input/case1test.json
```

### 选项参数

- `--output <path>` - 指定输出脚本路径（默认自动生成）
- `--no-refine` - 跳过脚本精炼步骤（更快但质量可能降低）
- `--keep-json` - 保留中间 JSON 文件（CSV 输入时）

## 📝 工作流程

```
CSV 文件
   ↓
JSON (步骤作为背景知识)
   ↓
AI 分析 (理解测试目标)
   ↓
生成 PowerShell 脚本 (目标导向)
   ↓
AI 精炼 (检查最佳实践)
   ↓
输出可执行脚本
```

## 🤖 AI Prompt 设计

### 核心指令

```
你是 PowerShell 测试自动化专家。

任务：生成目标导向的测试脚本，而非逐步模拟人类操作。

关键原则：
1. 人类步骤是背景知识，不是模拟指令
2. 专注测试目标：安装 → 验证 → 清理
3. 所有操作必须静默（无 UI）
4. 使用 PowerShell 命令，避免 GUI 自动化
5. 通过脚本验证（注册表、服务、文件）
```

### 生成逻辑

AI 会分析人类步骤，提取：
- 被测软件是什么？(cmdextension.msi)
- 安装路径在哪？(C:\VMShare)
- 预期结果是什么？(服务、文件、注册表)
- 需要什么清理？(卸载)

然后生成包含以下阶段的脚本：
1. **PRE-CHECK** - 管理员权限、冲突检查
2. **INSTALLATION** - 静默安装 + 退出码验证
3. **VERIFICATION** - 所有预期结果的检查
4. **CLEANUP** - 静默卸载 + 清理验证

## ✅ 最佳实践保证

生成的脚本自动遵循：

- ✅ MSI 安装使用 `/qn` (完全静默)
- ✅ MSI 卸载使用 `/x /qn`
- ✅ 正确的服务名 `CloudManagedDesktopExtension`
- ✅ 退出码处理 (0, 3010=成功; 1603, 1618, 1925=失败)
- ✅ 日志文件记录 (`/l*v logfile.log`)
- ✅ 不使用 GUI 工具 (explorer.exe, services.msc, taskmgr.exe)
- ✅ 单个管理员会话执行
- ✅ 彩色输出和进度提示
- ✅ 结果汇总

## 🔧 依赖安装

```powershell
pip install openai azure-identity
```

## 🔐 认证配置

使用 Azure AD 认证（无需 API Key）：

```powershell
az login
```

或配置环境变量：
- `AZURE_CLIENT_ID`
- `AZURE_CLIENT_SECRET`
- `AZURE_TENANT_ID`

## 📊 示例输出

生成的 PowerShell 脚本结构：

```powershell
# ============================================================
# PHASE 1: PRE-CHECK
# ============================================================
Write-Host "Checking prerequisites..." -ForegroundColor Cyan
# ... 管理员权限检查、冲突检查

# ============================================================
# PHASE 2: INSTALLATION
# ============================================================
Write-Host "Installing Microsoft Cloud Managed Desktop Extension..." -ForegroundColor Cyan
$process = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i', '"C:\VMShare\cmdextension.msi"', '/qn', '/l*v', '"install.log"') -Wait -PassThru -NoNewWindow
# ... 退出码验证、服务启动等待

# ============================================================
# PHASE 3: VERIFICATION
# ============================================================
Write-Host "Verifying installation..." -ForegroundColor Cyan
# ... 服务检查、文件检查、注册表检查、任务计划检查

# ============================================================
# PHASE 4: CLEANUP
# ============================================================
Write-Host "Cleaning up..." -ForegroundColor Cyan
$process = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/x', '"C:\VMShare\cmdextension.msi"', '/qn', '/l*v', '"uninstall.log"') -Wait -PassThru -NoNewWindow
# ... 卸载验证

# ============================================================
# SUMMARY
# ============================================================
Write-Host "Test completed: X passed, Y failed" -ForegroundColor Green
```

## 🆚 与 V1 的区别

| 特性 | V1 (旧方案) | V2 (新方案) |
|------|-------------|-------------|
| 设计理念 | 逐步模拟人类操作 | 目标导向测试 |
| 脚本生成 | 每个 step 生成对应脚本 | 整体理解生成一个脚本 |
| UI 操作 | 打开 Explorer、services.msc | 完全避免 GUI |
| MSI 安装 | `/qn+` (有对话框) | `/qn` (完全静默) |
| 验证方式 | 视觉验证 + 脚本 | 纯脚本验证 |
| 执行方式 | 多个窗口/会话 | 单一管理员会话 |
| AI 角色 | 生成操作命令 | 理解意图生成方案 |

## 📄 许可

MIT License

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

---

**Auto-Test V2** - 让自动化测试回归本质：目标验证，而非操作模拟
