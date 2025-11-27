# LangGraph 卡住问题诊断

## 问题描述
运行 `python cli_langgraph.py input/case1test.csv` 时卡在 "✅ Script generated" 之后

## 错误分析

### ❌ 最初的误判
我一开始以为是 `model_client.py` 的 Azure AD 认证问题，但这是**错的**！

**证据**：
- 如果是认证问题，脚本生成会失败
- 但输出显示 "✅ Script generated"，说明 AI 调用成功
- 所以认证是正常的，**不需要修改 model_client.py**

### ✅ 真正的问题
问题出在 **LangGraph workflow 的创建/执行**

**定位过程**：
1. 创建 `debug_workflow.py` 逐步测试每个节点 → 卡住
2. 创建 `test_langgraph_simple.py` 只测试导入 → 在 `import auto_test_workflow` 时卡住
3. 发现 `core/graph.py` 第158行在模块加载时就创建 workflow

**根本原因**：
```python
# 原代码（有问题）
auto_test_workflow = create_workflow()  ← 模块加载时立即执行
```

当您 `import core.graph` 时，`workflow.compile()` 被调用，这个过程可能：
- 卡在编译阶段
- 或者编译成功但 `invoke()/stream()` 卡住

## 已实施的修复

### 修改 `core/graph.py`

```python
# 延迟创建 workflow
_auto_test_workflow = None

def get_workflow():
    """Get or create the auto-test workflow instance"""
    global _auto_test_workflow
    if _auto_test_workflow is None:
        print("🔧 Compiling LangGraph workflow...")
        _auto_test_workflow = create_workflow()
        print("✅ Workflow compiled")
    return _auto_test_workflow

# 在 run_auto_test 和 stream_auto_test 中使用
workflow = get_workflow()
```

## 可能仍然存在的问题

即使延迟加载了，workflow 可能还会在以下地方卡住：

### 1. `workflow.compile()` 卡住
**症状**：永远看不到 "✅ Workflow compiled"

**可能原因**：
- LangGraph 版本问题
- 循环依赖检测耗时过长
- TypedDict 类型检查问题

**解决方案**：
```python
# 检查 LangGraph 版本
pip show langgraph

# 尝试降级到稳定版本
pip install langgraph==0.1.0
```

### 2. `workflow.invoke()` 或 `workflow.stream()` 卡住
**症状**：能看到 "✅ Workflow compiled"，但之后没有输出

**可能原因**：
- 某个节点函数死循环
- 条件边逻辑错误导致死循环
- 节点内部阻塞（如等待输入）

**调试方法**：
```python
# 在每个节点函数开始添加打印
def parse_csv_node(state):
    print("DEBUG: Entering parse_csv_node")
    # ... 原有代码
    print("DEBUG: Exiting parse_csv_node")
    return state
```

## 建议的下一步

### 方案 1：检查 LangGraph 安装
```powershell
pip list | findstr langgraph
```

### 方案 2：测试最小 LangGraph 示例
```python
from langgraph.graph import StateGraph, END
from typing import TypedDict

class State(TypedDict):
    count: int

def increment(state: State) -> State:
    print(f"Count: {state['count']}")
    return {"count": state["count"] + 1}

workflow = StateGraph(State)
workflow.add_node("increment", increment)
workflow.set_entry_point("increment")
workflow.add_edge("increment", END)
app = workflow.compile()

# 测试
result = app.invoke({"count": 0})
print(f"Final: {result}")
```

### 方案 3：回退到简单的顺序执行
如果 LangGraph 持续有问题，可以暂时不用它，直接顺序调用节点：

```python
def run_auto_test_simple(csv_path, test_case_id=""):
    state = create_initial_state(csv_path, test_case_id)
    
    state = parse_csv_node(state)
    if state.get("errors"): return state
    
    state = generate_script_node(state)
    if state.get("errors"): return state
    
    state = validate_script_node(state)
    if not state.get("validation_passed"): return state
    
    state = execute_test_node(state)
    state = wait_for_completion_node(state)
    state = analyze_logs_node(state)
    state = generate_report_node(state)
    
    return state
```

## 总结

- ✅ 已修复：延迟 workflow 创建
- ❌ **没有**修改 `model_client.py`（认证是正常的）
- ⏳ 待确认：LangGraph 本身是否正常工作

您可以先检查 LangGraph 安装，如果还有问题，我们可以添加更详细的调试日志或者暂时绕过 LangGraph。
