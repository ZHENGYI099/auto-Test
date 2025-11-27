# LangGraph 版本快速开始指南

## ✅ 已完成的功能

### 核心架构
- ✅ **状态管理** (`core/state.py`) - 统一的 `AutoTestState` 类型定义
- ✅ **工作流节点** (`core/nodes/`) - 7个纯函数节点
  - `parse.py` - CSV解析
  - `generate.py` - AI生成脚本
  - `validate.py` - 脚本验证
  - `execute.py` - PowerShell执行
  - `wait.py` - 等待完成
  - `analyze.py` - AI日志分析
  - `report.py` - HTML报告生成
- ✅ **工作流图** (`core/graph.py`) - LangGraph编排逻辑
- ✅ **命令行接口** (`cli_langgraph.py`) - 测试工具

## 🚀 如何使用

### 1. 安装依赖

```powershell
cd auto-test-v2
pip install -r requirements.txt
```

这会安装:
- `langgraph>=0.2.0`
- `langchain-core>=0.3.0`
- `langchain-openai>=0.2.0`

### 2. 命令行测试

#### 简单模式（一次性运行）
```powershell
python cli_langgraph.py input/case1.csv
```

#### 指定测试用例ID
```powershell
python cli_langgraph.py input/case1.csv case1
```

#### 流式模式（查看每个步骤）
```powershell
python cli_langgraph.py input/case1.csv case1 --stream
```

### 3. 工作流程图

```
START
  ↓
[Parse CSV] ────────→ (parse failed) → END
  ↓ (success)
[Generate Script]
  ↓
[Validate Script] ──→ (critical issues) → END
  ↓ (passed/warnings)
[Execute Test]
  ↓
[Wait for Completion] ←─┐ (still running)
  ↓ (completed)          │
  ├──────────────────────┘
  ↓
[Analyze Logs]
  ↓
[Generate Report]
  ↓
END
```

## 🆚 对比：旧版 vs LangGraph版

### 旧版 (`gui_client.py`)
```python
# 分散的状态管理
self.latest_script_path = None
self.latest_log_file = None
self.latest_report_path = None

# 线程 + 队列通信
self.output_queue.put(("log", "message", "info"))

# 回调函数传递状态
def _run_test_thread(self, script_path):
    # ... 复杂的状态更新逻辑
```

### LangGraph版 (`core/graph.py`)
```python
# 统一的状态对象
state = {
    "csv_path": "...",
    "generated_script_path": "...",
    "log_file_path": "...",
    "report_path": "...",
    # ... 所有状态都在这里
}

# 纯函数节点
def generate_script_node(state: AutoTestState) -> AutoTestState:
    # 输入state，输出新state
    # 无副作用，易测试
    return {**state, "generated_script_path": path}

# 声明式工作流
workflow.add_edge("parse_csv", "generate_script")
workflow.add_conditional_edges("validate_script", should_continue, {...})
```

## 💡 核心优势

### 1. **状态管理清晰**
```python
# 一眼看清所有状态
print(state.keys())
# => csv_path, test_case_id, parsed_data, generated_script_path, 
#    validation_issues, test_logs, ai_analysis, report_path, errors, ...
```

### 2. **流程可视化**
```python
from core.graph import auto_test_workflow

# 生成Mermaid流程图
graph = auto_test_workflow.get_graph()
print(graph.draw_mermaid())
```

### 3. **错误处理统一**
```python
# 每个节点返回errors列表
return {
    **state,
    "errors": state["errors"] + ["Something went wrong"]
}

# 条件边检查错误
def should_continue(state):
    if state.get("errors"):
        return "end"
    return "continue"
```

### 4. **可测试性**
```python
# 每个节点都是纯函数，易于单元测试
def test_parse_csv_node():
    state = {"csv_path": "test.csv", "errors": []}
    result = parse_csv_node(state)
    assert result["parsed_data"] is not None
    assert len(result["errors"]) == 0
```

### 5. **流式执行**
```python
# 实时查看每个步骤的输出
for step in stream_auto_test("input/case1.csv"):
    for node_name, state in step.items():
        print(f"Completed: {node_name}")
        print(f"Current step: {state['current_step']}")
```

## 📋 下一步计划

### Phase 1: 测试和修复 (现在可以做)
- [ ] 运行 `cli_langgraph.py` 测试基本流程
- [ ] 修复可能的import错误
- [ ] 验证每个节点的逻辑

### Phase 2: GUI集成 (可选)
- [ ] 创建 `gui_langgraph.py`
- [ ] 将状态更新映射到tkinter组件
- [ ] 添加进度条显示当前节点

### Phase 3: 高级功能 (扩展)
- [ ] 添加人工审核节点 (human-in-the-loop)
- [ ] 实现checkpointing (保存/恢复)
- [ ] 并行执行多个测试用例
- [ ] 集成LangSmith进行调试

## 🐛 可能需要修复的问题

1. **Import路径** - 节点中的import可能需要调整
2. **CSV Parser** - 确保 `parse_csv` 方法名正确
3. **Test Generator** - 确保 `generate_test_script` 方法签名匹配
4. **类型检查** - TypedDict可能需要 `typing_extensions`

## 🎯 现在就试试！

```powershell
# 1. 确保在虚拟环境中
.\.venv\Scripts\Activate.ps1

# 2. 进入目录
cd auto-test-v2

# 3. 测试运行（用现有的CSV文件）
python cli_langgraph.py input/case1.csv --stream
```

如果遇到错误，复制错误信息给我，我会帮你修复！
