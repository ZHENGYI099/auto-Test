# 输出目录说明

## 目录结构

项目现在有**两个独立的输出目录**，分别对应两个版本：

```
auto-test-v2/
├── output/              # 旧版本 (gui_client.py) 的输出
│   ├── test_*.ps1       # 生成的测试脚本
│   ├── logs/            # PowerShell 执行日志
│   └── reports/         # HTML 测试报告
│
├── output_langgraph/    # LangGraph 版本的输出 ✨ NEW
│   ├── test_*.ps1       # 生成的测试脚本
│   ├── logs/            # PowerShell 执行日志
│   └── reports/         # HTML 测试报告
│
└── ...
```

## 为什么分开？

### ✅ 优点

1. **避免混淆**
   - 两个版本的日志不会互相干扰
   - 可以对比同一个测试用例在两个版本中的结果

2. **方便测试**
   - 同时运行两个版本，输出互不影响
   - 保留历史记录，方便调试

3. **清晰的版本隔离**
   - `output/` = 稳定的旧版本
   - `output_langgraph/` = 实验性的 LangGraph 版本

### 📁 文件命名规则

两个版本使用相同的命名规则：

```
# 脚本
test_case1test.ps1

# 日志
test_case1test_20251125_161204.log

# 报告
report_case1test_20251125_161204.html
```

## 使用指南

### 旧版本 GUI
```powershell
python gui_client.py
```
- 输出位置: `output/`
- 功能: 完整的 GUI 界面

### LangGraph 版本 CLI
```powershell
python cli_langgraph.py input/case1test.csv --stream
```
- 输出位置: `output_langgraph/`
- 功能: 流式工作流，命令行界面

### 查看结果

#### 旧版本
```powershell
# 查看脚本
ls output/*.ps1

# 查看日志
ls output/logs/*.log

# 查看报告
ls output/reports/*.html
```

#### LangGraph 版本
```powershell
# 查看脚本
ls output_langgraph/*.ps1

# 查看日志
ls output_langgraph/logs/*.log

# 查看报告
ls output_langgraph/reports/*.html
```

## 清理输出

### 清理旧版本输出
```powershell
Remove-Item -Recurse -Force output/
```

### 清理 LangGraph 输出
```powershell
Remove-Item -Recurse -Force output_langgraph/
```

### 清理所有输出
```powershell
Remove-Item -Recurse -Force output/, output_langgraph/
```

## 对比结果

如果你想对比两个版本对同一个测试用例的处理结果：

```powershell
# 1. 运行旧版本
python gui_client.py
# 选择 case1test.csv，生成并运行

# 2. 运行 LangGraph 版本
python cli_langgraph.py input/case1test.csv --stream

# 3. 对比报告
# 旧版本: output/reports/report_case1test_*.html
# 新版本: output_langgraph/reports/report_case1test_*.html
```

## 技术细节

### 日志路径替换

LangGraph 版本在生成脚本时会自动替换日志路径：

```powershell
# 原始模板
$logDir = "$PSScriptRoot\\..\\output\\logs"

# LangGraph 版本替换为
$logDir = "D:\auto-Test\auto-test-v2\output_langgraph\logs"
```

这确保了两个版本的日志完全独立存储。

### 报告生成

报告生成后会自动移动到正确的目录：

```python
# generate_report_node 会：
1. 使用 ReportGenerator 生成临时报告
2. 复制到 output_langgraph/reports/
3. 删除临时文件
```

## 未来计划

当 LangGraph 版本足够稳定后，可以：
1. 逐步迁移所有功能到 LangGraph
2. 废弃旧版本，统一使用 `output/`
3. 或者保留两个版本供不同场景使用
