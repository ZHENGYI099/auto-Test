# Auto-Test-v2 LangGraph 重构设计

## 核心优势

### 1. 可视化工作流
```
START
  ↓
[Parse CSV] ─────────────→ (validation error) → END
  ↓
[Generate Script]
  ↓
[Validate Script] ─────→ (has warnings) → [Human Review] → [Continue/Abort]
  ↓
[Execute Test]
  ↓
[Wait for Completion] ←─ (polling loop)
  ↓
[Analyze Logs with AI]
  ↓
[Generate Report]
  ↓
END
```

### 2. 状态管理
**统一的 State 对象替代分散的实例变量:**
```python
class AutoTestState(TypedDict):
    # Input
    csv_path: str
    test_case_id: str
    
    # Intermediate results
    parsed_data: dict
    generated_script_path: str
    validation_issues: list[dict]
    
    # Execution
    process_id: Optional[int]
    log_file_path: Optional[str]
    execution_status: str  # "running", "completed", "failed"
    
    # Output
    test_logs: str
    ai_analysis: str
    report_path: str
    
    # Error handling
    errors: list[str]
    retry_count: int
```

### 3. 节点定义 (Nodes)
```python
# 每个节点都是一个纯函数，输入和输出都是 State
def parse_csv_node(state: AutoTestState) -> AutoTestState:
    """Parse CSV file and extract test case data"""
    csv_path = state["csv_path"]
    parser = CSVParser()
    try:
        data = parser.parse(csv_path)
        return {**state, "parsed_data": data}
    except Exception as e:
        return {**state, "errors": state["errors"] + [str(e)]}

def generate_script_node(state: AutoTestState) -> AutoTestState:
    """Generate PowerShell test script using AI"""
    generator = TestGenerator()
    script_path = generator.generate(state["parsed_data"])
    return {**state, "generated_script_path": script_path}

def validate_script_node(state: AutoTestState) -> AutoTestState:
    """Validate generated script"""
    validator = ScriptValidator()
    issues = validator.validate_script(state["generated_script_path"])
    return {**state, "validation_issues": issues}

def execute_test_node(state: AutoTestState) -> AutoTestState:
    """Execute PowerShell test script"""
    # Launch PowerShell process
    process = launch_powershell(state["generated_script_path"])
    return {**state, "process_id": process.pid, "execution_status": "running"}

def wait_for_completion_node(state: AutoTestState) -> AutoTestState:
    """Wait for test execution to complete"""
    log_path = wait_for_log_completion(state["process_id"])
    with open(log_path, 'r') as f:
        logs = f.read()
    return {**state, "log_file_path": log_path, "test_logs": logs, "execution_status": "completed"}

def analyze_logs_node(state: AutoTestState) -> AutoTestState:
    """AI analysis of test logs"""
    model_client = ModelClient()
    analysis = model_client.analyze_logs(state["test_logs"], state["test_case_id"])
    return {**state, "ai_analysis": analysis}

def generate_report_node(state: AutoTestState) -> AutoTestState:
    """Generate HTML report"""
    report_gen = ReportGenerator()
    report_path = report_gen.generate_html_report(
        test_case_id=state["test_case_id"],
        script_path=state["generated_script_path"],
        logs=state["test_logs"],
        ai_analysis=state["ai_analysis"],
        validation_report=format_validation(state["validation_issues"])
    )
    return {**state, "report_path": report_path}
```

### 4. 条件边 (Conditional Edges)
```python
def should_continue_after_validation(state: AutoTestState) -> str:
    """Decide whether to continue or abort after validation"""
    issues = state["validation_issues"]
    
    # Critical errors → abort
    if any(i["severity"] == "critical" for i in issues):
        return "abort"
    
    # Warnings → human review
    if any(i["severity"] == "warning" for i in issues):
        return "review"
    
    # All good → continue
    return "execute"

def check_execution_status(state: AutoTestState) -> str:
    """Check if test execution completed"""
    if state["execution_status"] == "completed":
        return "analyze"
    elif state["execution_status"] == "failed":
        return "retry" if state["retry_count"] < 3 else "abort"
    else:
        return "wait"  # Keep polling
```

### 5. 图构建 (Graph Construction)
```python
from langgraph.graph import StateGraph, END

# Create graph
workflow = StateGraph(AutoTestState)

# Add nodes
workflow.add_node("parse_csv", parse_csv_node)
workflow.add_node("generate_script", generate_script_node)
workflow.add_node("validate_script", validate_script_node)
workflow.add_node("human_review", human_review_node)  # For GUI interaction
workflow.add_node("execute_test", execute_test_node)
workflow.add_node("wait_completion", wait_for_completion_node)
workflow.add_node("analyze_logs", analyze_logs_node)
workflow.add_node("generate_report", generate_report_node)

# Define edges
workflow.set_entry_point("parse_csv")
workflow.add_edge("parse_csv", "generate_script")
workflow.add_edge("generate_script", "validate_script")

# Conditional edge after validation
workflow.add_conditional_edges(
    "validate_script",
    should_continue_after_validation,
    {
        "execute": "execute_test",
        "review": "human_review",
        "abort": END
    }
)

workflow.add_edge("human_review", "execute_test")  # After review, continue
workflow.add_edge("execute_test", "wait_completion")

# Polling loop for waiting
workflow.add_conditional_edges(
    "wait_completion",
    check_execution_status,
    {
        "analyze": "analyze_logs",
        "wait": "wait_completion",  # Loop back
        "retry": "execute_test",
        "abort": END
    }
)

workflow.add_edge("analyze_logs", "generate_report")
workflow.add_edge("generate_report", END)

# Compile graph
app = workflow.compile()
```

### 6. GUI 集成
```python
# 在 gui_client.py 中
def generate_and_run_test(self):
    """使用 LangGraph 执行完整工作流"""
    initial_state = {
        "csv_path": self.csv_path.get(),
        "test_case_id": self.test_case_id.get(),
        "errors": [],
        "retry_count": 0
    }
    
    # Stream execution to get intermediate results
    for state in app.stream(initial_state):
        # Update GUI with current state
        self.update_progress(state)
        
        # Check if human review needed
        if "human_review" in state:
            # Show dialog and wait for user input
            decision = self.show_review_dialog(state["validation_issues"])
            if decision == "abort":
                break
    
    # Final state
    final_state = state
    self.show_report(final_state["report_path"])
```

### 7. 人机交互节点 (Human-in-the-Loop)
```python
def human_review_node(state: AutoTestState) -> AutoTestState:
    """Pause for human review of validation issues"""
    # This would integrate with GUI
    # In LangGraph, you can use interrupts for this
    return state  # GUI handles the interaction

# Enable interrupts when compiling
app = workflow.compile(
    checkpointer=MemorySaver(),  # Save state for resuming
    interrupt_before=["human_review"]  # Pause before this node
)

# In GUI:
# 1. Run until interrupt
# 2. Show review dialog
# 3. User decides
# 4. Resume execution
```

## 核心优势总结

### ✅ 优点
1. **状态管理统一** - 不再需要 `self.latest_*` 变量到处传递
2. **流程可视化** - 可以用 `app.get_graph().draw_mermaid()` 生成流程图
3. **错误恢复** - LangGraph 支持 checkpointing，可以从失败点恢复
4. **并行执行** - 可以轻松添加并行节点（如同时生成多个测试脚本）
5. **可测试性** - 每个节点都是纯函数，容易单元测试
6. **人机协作** - 内置 interrupt 机制，支持人工审核
7. **可观测性** - 内置 tracing 和 logging

### ⚠️ 考虑因素
1. **学习曲线** - 团队需要学习 LangGraph 概念
2. **依赖增加** - 需要安装 `langgraph` 和 `langchain-core`
3. **GUI 集成复杂度** - 需要重新设计 tkinter 和 LangGraph 的集成方式

## 推荐实施步骤

### Phase 1: 核心工作流
- [ ] 定义 `AutoTestState` TypedDict
- [ ] 实现基础节点（parse, generate, validate, execute, analyze, report）
- [ ] 构建基础图（无 GUI）
- [ ] 命令行测试

### Phase 2: GUI 集成
- [ ] 实现状态流式更新到 GUI
- [ ] 添加进度条和实时日志
- [ ] 集成人工审核节点

### Phase 3: 高级功能
- [ ] 添加错误重试逻辑
- [ ] 实现 checkpointing（保存/恢复会话）
- [ ] 添加并行测试执行
- [ ] 集成 LangSmith 进行调试

## 示例代码结构
```
auto-test-v2/
├── core/
│   ├── nodes/              # LangGraph 节点
│   │   ├── __init__.py
│   │   ├── parse.py
│   │   ├── generate.py
│   │   ├── validate.py
│   │   ├── execute.py
│   │   ├── analyze.py
│   │   └── report.py
│   ├── graph.py            # 图定义
│   ├── state.py            # State TypedDict
│   └── ...
├── gui_langgraph.py        # 新的 GUI 集成
└── cli_langgraph.py        # 命令行接口
```

## 是否值得重构？

**推荐使用 LangGraph 如果:**
- ✅ 项目会持续扩展（添加更多测试类型、步骤）
- ✅ 需要复杂的条件分支逻辑
- ✅ 需要人工审核步骤
- ✅ 需要可视化工作流
- ✅ 需要错误恢复和重试机制

**保持当前架构如果:**
- ❌ 项目功能已经稳定，不再扩展
- ❌ 团队不熟悉 LangChain/LangGraph
- ❌ 简单的线性流程足够
