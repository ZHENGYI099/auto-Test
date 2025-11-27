"""
Auto-Test V2 - Desktop GUI Client
桌面客户端 - 支持 CSV 上传、脚本生成、测试执行和实时状态显示

功能:
1. CSV 文件选择和上传
2. 自动生成 PowerShell 测试脚本
3. 以管理员权限执行测试
4. 实时显示测试状态和结果
5. 支持查看测试日志
"""
import tkinter as tk
from tkinter import ttk, filedialog, messagebox, scrolledtext
import subprocess
import threading
import json
import sys
from pathlib import Path
from datetime import datetime
import queue
import os
import re
import webbrowser

# Add current directory to path for imports
sys.path.insert(0, str(Path(__file__).parent))

try:
    from core.csv_parser import parse_csv_to_json, save_json
    from core.test_generator import TestScriptGenerator
    from core.script_validator import ScriptValidator
    from core.report_generator import ReportGenerator
    HAS_CORE = True
except ImportError as e:
    # Fallback: 如果找不到模块，提示用户
    HAS_CORE = False
    print(f"警告: 无法导入核心模块 - {e}")
    print("请确保在 auto-test-v2 目录中运行")
    
    def parse_csv_to_json(csv_path):
        """临时占位函数"""
        raise ImportError("核心模块未找到，请在 auto-test-v2 目录中运行客户端")
    
    def save_json(data, path):
        """临时占位函数"""
        raise ImportError("核心模块未找到，请在 auto-test-v2 目录中运行客户端")
    
    class TestScriptGenerator:
        """临时占位类"""
        def __init__(self):
            raise ImportError("核心模块未找到，请在 auto-test-v2 目录中运行客户端")


class AutoTestGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("🚀 Auto-Test V2 - Automated Testing Client")
        self.root.geometry("1100x800")
        self.root.minsize(1000, 700)
        
        # 配置窗口样式 - Teams 风格背景色
        self.root.configure(bg='#f3f2f1')
        
        # 设置图标（如果有的话）
        try:
            self.root.iconbitmap('icon.ico')
        except:
            pass
        
        # Variables
        self.csv_path = tk.StringVar()
        self.output_path = tk.StringVar()
        self.existing_script_path = tk.StringVar()
        self.test_case_id = tk.StringVar()
        self.status_var = tk.StringVar(value="Ready")
        self.progress_var = tk.DoubleVar(value=0)
        
        # Store last AI evaluation results
        self.last_evaluation = None
        
        # Test process
        self.test_process = None
        self.is_running = False
        
        # Report paths
        self.latest_report_path = None
        self.latest_log_file = None
        self.latest_script_path = None  # Track last executed script
        
        # Output queue (for thread communication)
        self.output_queue = queue.Queue()
        
        # Create UI
        self.create_widgets()
        
        # Start output monitoring
        self.check_output_queue()
    
    def create_widgets(self):
        """Create all UI widgets - Microsoft Teams Style"""
        # 配置 Teams 风格样式
        style = ttk.Style()
        
        # Teams 风格按钮 - 圆润、阴影效果
        style.configure('Teams.TButton', 
                       font=('Segoe UI', 10),
                       padding=(20, 10),
                       relief='flat',
                       borderwidth=0)
        
        # 主按钮 - Teams 紫色
        style.map('Teams.TButton',
                 background=[('active', '#6264a7'), ('!disabled', '#6264a7')],
                 foreground=[('!disabled', 'white')])
        
        # 次要按钮 - 浅灰色
        style.configure('Secondary.TButton',
                       font=('Segoe UI', 10),
                       padding=(20, 10))
        
        # 危险按钮 - 红色
        style.configure('Danger.TButton',
                       font=('Segoe UI', 10),
                       padding=(15, 8))
        
        # 进度条 - Teams 紫色
        style.configure('Teams.Horizontal.TProgressbar',
                       troughcolor='#e1dfdd',
                       background='#6264a7',
                       thickness=8,
                       borderwidth=0)
        
        # Main frame - Teams 浅灰背景
        main_frame = tk.Frame(self.root, bg='#f3f2f1')
        main_frame.grid(row=0, column=0, sticky=(tk.W, tk.E, tk.N, tk.S), padx=20, pady=20)
        
        self.root.columnconfigure(0, weight=1)
        self.root.rowconfigure(0, weight=1)
        main_frame.columnconfigure(0, weight=1)
        main_frame.rowconfigure(3, weight=1)
        
        # ========== Title Area (Teams Style Header with gradient) ==========
        title_frame = tk.Frame(main_frame, bg='#6264a7', relief=tk.FLAT, height=100)
        title_frame.grid(row=0, column=0, sticky=(tk.W, tk.E), pady=(0, 20))
        title_frame.columnconfigure(0, weight=1)
        title_frame.grid_propagate(False)  # 固定高度
        
        # Title with larger, modern font
        title_label = tk.Label(title_frame, text="🚀 Auto-Test V2", 
                              font=('Segoe UI', 22, 'bold'), 
                              bg='#6264a7', fg='white',
                              anchor='w')
        title_label.grid(row=0, column=0, sticky=(tk.W, tk.E), padx=25, pady=(20, 5))
        
        # Subtitle with lighter text
        subtitle_label = tk.Label(title_frame, 
                                 text="AI-Powered Test Script Generation & Execution Platform", 
                                 font=('Segoe UI', 11), 
                                 bg='#6264a7', fg='#e8e8f8',
                                 anchor='w')
        subtitle_label.grid(row=1, column=0, sticky=(tk.W, tk.E), padx=25, pady=(0, 15))
        
        # ========== CSV File Selection Area (Teams Card Style) ==========
        file_frame = tk.Frame(main_frame, bg='white', relief=tk.FLAT)
        file_frame.grid(row=1, column=0, sticky=(tk.W, tk.E), pady=(0, 15))
        file_frame.columnconfigure(1, weight=1)
        
        # Card header with Teams style
        header_label = tk.Label(file_frame, text="📁 Step 1: Select Test Case File",
                               font=('Segoe UI', 13, 'bold'),
                               fg='#252423', bg='white', anchor='w')
        header_label.grid(row=0, column=0, columnspan=3, sticky=(tk.W, tk.E), 
                         padx=25, pady=(20, 15))
        
        # CSV File row - Teams modern styling
        tk.Label(file_frame, text="CSV File", font=('Segoe UI', 10),
                fg='#605e5c', bg='white').grid(row=1, column=0, sticky=tk.W, padx=(25, 15))
        
        # Custom styled entry with border frame
        csv_entry_frame = tk.Frame(file_frame, bg='#edebe9', relief=tk.FLAT, bd=0)
        csv_entry_frame.grid(row=1, column=1, sticky=(tk.W, tk.E), padx=(0, 10))
        
        csv_entry = tk.Entry(csv_entry_frame, textvariable=self.csv_path, 
                            state='readonly', font=('Segoe UI', 10),
                            bg='#faf9f8', fg='#252423', relief=tk.FLAT,
                            bd=0, highlightthickness=1, highlightcolor='#6264a7',
                            highlightbackground='#edebe9')
        csv_entry.pack(fill=tk.BOTH, expand=True, padx=1, pady=1)
        
        browse_btn = tk.Button(file_frame, text="📂 Browse", 
                              command=self.select_csv_file,
                              font=('Segoe UI', 10),
                              bg='#6264a7', fg='white',
                              relief=tk.FLAT, bd=0,
                              padx=20, pady=8,
                              cursor='hand2',
                              activebackground='#464775',
                              activeforeground='white')
        browse_btn.grid(row=1, column=2, padx=(0, 25))
        
        # Test Case ID row - Teams modern styling
        tk.Label(file_frame, text="Test Case ID", font=('Segoe UI', 10),
                fg='#605e5c', bg='white').grid(row=2, column=0, sticky=tk.W, 
                                               padx=(25, 15), pady=(15, 0))
        
        # Custom styled entry for ID with border frame
        id_entry_frame = tk.Frame(file_frame, bg='#edebe9', relief=tk.FLAT, bd=0)
        id_entry_frame.grid(row=2, column=1, sticky=(tk.W, tk.E), padx=(0, 10), pady=(15, 0))
        
        id_entry = tk.Entry(id_entry_frame, textvariable=self.test_case_id, 
                           font=('Segoe UI', 10),
                           bg='white', fg='#252423', relief=tk.FLAT,
                           bd=0, highlightthickness=1, highlightcolor='#6264a7',
                           highlightbackground='#edebe9')
        id_entry.pack(fill=tk.BOTH, expand=True, padx=1, pady=1)
        
        tk.Label(file_frame, text="(auto-detected)", font=('Segoe UI', 9, 'italic'),
                fg='#a19f9d', bg='white').grid(row=2, column=2, sticky=tk.W, 
                                               pady=(15, 0), padx=(0, 25))
        
        # Bottom padding for card
        tk.Frame(file_frame, bg='white', height=20).grid(row=3, column=0, columnspan=3)
        
        # ========== Action Buttons Area (Card Style) ==========
        action_frame = tk.LabelFrame(main_frame, text="  ⚙️ Step 2: Generate & Execute Test  ",
                                    font=('Segoe UI', 10, 'bold'),
                                    fg='#2c3e50', bg='white',
                                    relief=tk.GROOVE, bd=2, padx=15, pady=15)
        action_frame.grid(row=2, column=0, sticky=(tk.W, tk.E), pady=(0, 12))
        action_frame.columnconfigure(0, weight=1)
        
        # Row 1: Generate & Run buttons with modern style
        btn_frame1 = tk.Frame(action_frame, bg='white')
        btn_frame1.grid(row=0, column=0, sticky=(tk.W, tk.E), pady=(0, 8))
        
        self.generate_btn = ttk.Button(btn_frame1, text="🤖 Generate Script", 
                                       command=self.generate_script, width=22,
                                       style='Action.TButton')
        self.generate_btn.grid(row=0, column=0, padx=(0, 8))
        
        self.run_btn = ttk.Button(btn_frame1, text="▶️  Run Generated", 
                                  command=self.run_test, width=22, 
                                  style='Action.TButton', state='disabled')
        self.run_btn.grid(row=0, column=1, padx=(0, 8))
        
        output_btn = ttk.Button(btn_frame1, text="📁 Output Dir", 
                               command=self.open_output_dir, width=15,
                               style='Action.TButton')
        output_btn.grid(row=0, column=2, padx=(0, 8))
        
        self.view_report_btn = ttk.Button(btn_frame1, text="📊 View Report", 
                                         command=self.view_report, width=15,
                                         style='Action.TButton', state='disabled')
        self.view_report_btn.grid(row=0, column=3, padx=(0, 8))
        
        # Add Generate Report button
        self.gen_report_btn = ttk.Button(btn_frame1, text="📝 Generate Report", 
                                        command=self.generate_report_manually, width=18,
                                        style='Action.TButton', state='disabled')
        self.gen_report_btn.grid(row=0, column=4)
        
        # Separator line
        separator1 = ttk.Separator(action_frame, orient='horizontal')
        separator1.grid(row=1, column=0, sticky=(tk.W, tk.E), pady=10)
        
        # Row 2: Existing script buttons
        btn_frame2 = tk.Frame(action_frame, bg='white')
        btn_frame2.grid(row=2, column=0, sticky=(tk.W, tk.E), pady=(0, 8))
        
        select_btn = ttk.Button(btn_frame2, text="� Select Existing Script", 
                               command=self.select_existing_script, width=22,
                               style='Action.TButton')
        select_btn.grid(row=0, column=0, padx=(0, 8))
        
        self.run_existing_btn = ttk.Button(btn_frame2, text="▶️  Run Selected", 
                                           command=self.run_existing_test, width=22, 
                                           style='Action.TButton', state='disabled')
        self.run_existing_btn.grid(row=0, column=1, padx=(0, 8))
        
        self.stop_btn = ttk.Button(btn_frame2, text="⏹️  Stop Test", 
                                   command=self.stop_test, width=15,
                                   style='Action.TButton', state='disabled')
        self.stop_btn.grid(row=0, column=2)
        
        # Separator line
        separator2 = ttk.Separator(action_frame, orient='horizontal')
        separator2.grid(row=3, column=0, sticky=(tk.W, tk.E), pady=10)
        
        # Status section with icon
        status_container = tk.Frame(action_frame, bg='white')
        status_container.grid(row=4, column=0, sticky=(tk.W, tk.E))
        
        tk.Label(status_container, text="📊 Status:", 
                font=('Segoe UI', 9, 'bold'), bg='white', fg='#34495e').grid(
                row=0, column=0, sticky=tk.W, pady=(0, 5))
        
        self.status_label = tk.Label(status_container, textvariable=self.status_var,
                                     font=('Segoe UI', 9), bg='white', fg='#27ae60')
        self.status_label.grid(row=0, column=1, sticky=tk.W, padx=(8, 0), pady=(0, 5))
        
        # Progress bar with modern style
        style.configure('Modern.Horizontal.TProgressbar', thickness=20)
        self.progress_bar = ttk.Progressbar(action_frame, mode='determinate', 
                                           variable=self.progress_var,
                                           style='Modern.Horizontal.TProgressbar')
        self.progress_bar.grid(row=5, column=0, sticky=(tk.W, tk.E), pady=(5, 0))
        
        # ========== Output Log Area (Modern Console Style) ==========
        output_frame = tk.LabelFrame(main_frame, text="  📊 Real-time Output Log  ",
                                    font=('Segoe UI', 10, 'bold'),
                                    fg='#2c3e50', bg='white',
                                    relief=tk.GROOVE, bd=2, padx=8, pady=8)
        output_frame.grid(row=3, column=0, sticky=(tk.W, tk.E, tk.N, tk.S))
        output_frame.columnconfigure(0, weight=1)
        output_frame.rowconfigure(0, weight=1)
        
        # Create scrolled text widget with dark console theme
        self.output_text = scrolledtext.ScrolledText(output_frame, wrap=tk.WORD, 
                                                      height=22, 
                                                      font=('Consolas', 9),
                                                      bg='#2c3e50',  # Dark background
                                                      fg='#ecf0f1',  # Light text
                                                      insertbackground='white',  # Cursor color
                                                      relief=tk.FLAT,
                                                      padx=10, pady=10)
        self.output_text.grid(row=0, column=0, sticky=(tk.W, tk.E, tk.N, tk.S))
        
        # Configure text tag colors (optimized for dark background)
        self.output_text.tag_config("success", foreground="#2ecc71", font=('Consolas', 9))
        self.output_text.tag_config("error", foreground="#e74c3c", font=('Consolas', 9))
        self.output_text.tag_config("warning", foreground="#f39c12", font=('Consolas', 9))
        self.output_text.tag_config("info", foreground="#3498db", font=('Consolas', 9))
        self.output_text.tag_config("pass", foreground="#2ecc71", font=('Consolas', 9, 'bold'))
        self.output_text.tag_config("fail", foreground="#e74c3c", font=('Consolas', 9, 'bold'))
        
        # Button bar for log controls
        log_btn_frame = tk.Frame(output_frame, bg='white')
        log_btn_frame.grid(row=1, column=0, sticky=tk.E, pady=(8, 0))
        
        ttk.Button(log_btn_frame, text="🗑️  Clear Log", 
                   command=self.clear_output, style='Action.TButton').grid(row=0, column=0)
        
        self.log_message("Welcome to Auto-Test V2 Desktop Client", "info")
        self.log_message("Please select a CSV file to begin testing...", "info")
    
    def select_csv_file(self):
        """Select CSV file"""
        filename = filedialog.askopenfilename(
            title="Select CSV Test File",
            filetypes=[("CSV Files", "*.csv"), ("All Files", "*.*")],
            initialdir=str(Path(__file__).parent / "input")
        )
        
        if filename:
            self.csv_path.set(filename)
            
            # Auto-extract test case ID
            file_stem = Path(filename).stem
            # Try to extract case123 or pure number
            match = re.search(r'case(\d+)|(\d+)', file_stem, re.IGNORECASE)
            if match:
                case_id = match.group(1) or match.group(2)
                self.test_case_id.set(f"case{case_id}")
            else:
                self.test_case_id.set(file_stem)
            
            self.log_message(f"Selected file: {Path(filename).name}", "success")
            self.run_btn.config(state='disabled')  # Need to regenerate
    
    def select_existing_script(self):
        """Select existing PowerShell script"""
        filename = filedialog.askopenfilename(
            title="Select Existing PowerShell Test Script",
            filetypes=[("PowerShell Scripts", "*.ps1"), ("All Files", "*.*")],
            initialdir=str(Path(__file__).parent / "output")
        )
        
        if filename:
            self.existing_script_path.set(filename)
            self.run_existing_btn.config(state='normal')
            
            self.log_message("━" * 60, "info")
            self.log_message(f"📄 Selected existing script: {Path(filename).name}", "success")
            self.log_message(f"   Path: {filename}", "info")
            self.log_message("✅ Click [Run Selected Script] to execute", "success")
            self.log_message("━" * 60, "info")
    
    def generate_script(self):
        """Generate PowerShell test script"""
        csv_file = self.csv_path.get()
        
        if not csv_file:
            messagebox.showwarning("Warning", "Please select a CSV file first!")
            return
        
        if not Path(csv_file).exists():
            messagebox.showerror("Error", "CSV file does not exist!")
            return
        
        # Disable buttons
        self.generate_btn.config(state='disabled')
        self.status_var.set("Generating test script...")
        self.progress_var.set(30)
        
        # Execute generation in new thread
        thread = threading.Thread(target=self._generate_script_thread, args=(csv_file,))
        thread.daemon = True
        thread.start()
    
    def _generate_script_thread(self, csv_file):
        """Thread function for script generation"""
        try:
            csv_path = Path(csv_file)
            
            self.output_queue.put(("log", "📄 Reading CSV file...", "info"))
            self.output_queue.put(("progress", 40))
            
            # Step 1: Convert CSV to JSON
            test_case = parse_csv_to_json(str(csv_file))
            
            # Use user-specified ID if provided
            if self.test_case_id.get().strip():
                test_case['test_case_id'] = self.test_case_id.get().strip()
            
            json_path = Path("input") / f"{test_case['test_case_id']}.json"
            json_path.parent.mkdir(exist_ok=True)
            
            save_json(test_case, str(json_path))
            
            self.output_queue.put(("log", f"✅ CSV conversion completed: {json_path.name}", "success"))
            self.output_queue.put(("log", f"   Test Case ID: {test_case['test_case_id']}", "info"))
            self.output_queue.put(("log", f"   Test Steps: {len(test_case['steps'])}", "info"))
            self.output_queue.put(("progress", 60))
            
            # Step 2: Generate PowerShell script
            self.output_queue.put(("log", "🤖 Generating PowerShell script (AI processing)...", "info"))
            
            generator = TestScriptGenerator()
            
            output_path = generator.generate_and_save(
                json_path=str(json_path),
                output_path=None,  # Auto-generate
                refine=True  # Enable refinement
            )
            
            self.output_queue.put(("progress", 90))
            self.output_queue.put(("log", f"✅ Test script generation completed!", "success"))
            self.output_queue.put(("log", f"📄 Output path: {output_path}", "success"))
            
            # Step 3: Validate generated script
            self.output_queue.put(("log", "🔍 Validating generated script...", "info"))
            try:
                with open(output_path, 'r', encoding='utf-8-sig') as f:
                    script_content = f.read()
                
                validator = ScriptValidator()
                validation_result = validator.validate_script(script_content)
                
                if validation_result['is_valid']:
                    self.output_queue.put(("log", "✅ Script validation passed!", "success"))
                else:
                    report = validator.get_validation_report()
                    self.output_queue.put(("log", "⚠️ Validation warnings/errors found:", "warning"))
                    for line in report.split('\n'):
                        if line.strip():
                            self.output_queue.put(("log", f"   {line}", "warning"))
            except Exception as e:
                self.output_queue.put(("log", f"⚠️ Validation error: {str(e)}", "warning"))
            
            # Step 4: AI Quality Evaluation
            self.output_queue.put(("log", "━" * 60, "info"))
            self.output_queue.put(("log", "🤖 Evaluating script quality with AI...", "info"))
            try:
                from core.script_evaluator import ScriptEvaluator
                
                evaluator = ScriptEvaluator()
                evaluation = evaluator.evaluate_script_quality(
                    script=script_content,
                    test_case_id=test_case['test_case_id'],
                    test_scenario=test_case.get('test_scenario', ''),
                    expected_steps=len(test_case.get('steps', []))
                )
                
                # Display evaluation results
                self.output_queue.put(("log", f"📊 Overall Quality Score: {evaluation['overall_score']}/100 (Grade: {evaluation['grade']})", "success"))
                self.output_queue.put(("log", "   Dimension Scores:", "info"))
                scores = evaluation.get('scores', {})
                self.output_queue.put(("log", f"   • Correctness:     {scores.get('correctness', 0)}/100", "info"))
                self.output_queue.put(("log", f"   • Completeness:    {scores.get('completeness', 0)}/100", "info"))
                self.output_queue.put(("log", f"   • Best Practices:  {scores.get('best_practices', 0)}/100", "info"))
                self.output_queue.put(("log", f"   • Robustness:      {scores.get('robustness', 0)}/100", "info"))
                self.output_queue.put(("log", f"   • Maintainability: {scores.get('maintainability', 0)}/100", "info"))
                
                # Show strengths
                if evaluation.get('strengths'):
                    self.output_queue.put(("log", "   ✅ Strengths:", "success"))
                    for strength in evaluation['strengths'][:3]:
                        self.output_queue.put(("log", f"      • {strength}", "success"))
                
                # Show weaknesses
                if evaluation.get('weaknesses'):
                    self.output_queue.put(("log", "   ⚠️ Areas for Improvement:", "warning"))
                    for weakness in evaluation['weaknesses'][:3]:
                        self.output_queue.put(("log", f"      • {weakness}", "warning"))
                
                # Store evaluation for later use in report
                self.last_evaluation = evaluation
                
            except Exception as e:
                self.output_queue.put(("log", f"⚠️ AI evaluation error: {str(e)}", "warning"))
                self.last_evaluation = None
            
            self.output_queue.put(("progress", 100))
            self.output_queue.put(("log", "━" * 60, "info"))
            self.output_queue.put(("log", "✅ You can now click [Run Test] button to execute", "success"))
            
            # Save output path and enable run button
            self.output_path.set(output_path)
            self.output_queue.put(("enable_run", True))
            self.output_queue.put(("status", "Script ready"))
            
        except Exception as e:
            self.output_queue.put(("log", f"❌ Generation failed: {str(e)}", "error"))
            self.output_queue.put(("status", "Generation failed"))
            self.output_queue.put(("progress", 0))
            import traceback
            self.output_queue.put(("log", traceback.format_exc(), "error"))
        finally:
            self.output_queue.put(("enable_generate", True))
    
    def run_test(self):
        """Execute PowerShell test script (with admin privileges) - Generated Script"""
        script_path = self.output_path.get()
        
        if not script_path or not Path(script_path).exists():
            messagebox.showerror("Error", "Test script does not exist. Please generate it first!")
            return
        
        self._execute_script(script_path, "generated")
    
    def run_existing_test(self):
        """Execute existing PowerShell test script (with admin privileges)"""
        script_path = self.existing_script_path.get()
        
        if not script_path or not Path(script_path).exists():
            messagebox.showerror("Error", "Please select an existing script first!")
            return
        
        self._execute_script(script_path, "existing")
    
    def _execute_script(self, script_path, source_type="generated"):
        """Common method to execute a PowerShell script
        
        Args:
            script_path: Path to the PowerShell script
            source_type: "generated" or "existing"
        """
        # Confirm execution
        script_name = Path(script_path).name
        if not messagebox.askyesno("Confirm Execution", 
                                   f"About to execute: {script_name}\n\n"
                                   "This will run with administrator privileges and may modify system.\n"
                                   "Continue?"):
            return
        
        self.is_running = True
        self.run_btn.config(state='disabled')
        self.run_existing_btn.config(state='disabled')
        self.stop_btn.config(state='normal')
        self.generate_btn.config(state='disabled')
        self.status_var.set("Test executing...")
        self.progress_var.set(0)
        
        self.log_message("━" * 60, "info")
        self.log_message(f"🚀 Starting test execution ({source_type} script)...", "info")
        self.log_message(f"📄 Script: {Path(script_path).name}", "info")
        self.log_message(f"📂 Path: {script_path}", "info")
        self.log_message("━" * 60, "info")
        
        # Execute test in new thread
        thread = threading.Thread(target=self._run_test_thread, args=(script_path,))
        thread.daemon = True
        thread.start()
    
    def _run_test_thread(self, script_path):
        """Thread function for test execution"""
        try:
            # Save script path for manual report generation
            self.latest_script_path = script_path
            
            # CRITICAL FIX: Convert to absolute path
            # When PowerShell runs as admin, working directory changes
            # Relative paths will fail, causing window to flash and exit
            abs_script_path = str(Path(script_path).resolve())
            
            # Use the exact command format that works manually
            # User confirmed this works: Start-Process powershell -Verb RunAs -ArgumentList "..."
            escaped_path = abs_script_path.replace('"', '`"')
            
            # Method 1: Try direct execution without subprocess wrapper
            cmd_string = f'Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"{escaped_path}`"" -WindowStyle Normal'
            
            cmd = [
                "powershell.exe",
                "-NoProfile",
                "-ExecutionPolicy", "Bypass",
                "-Command",
                cmd_string
            ]
            
            # Log the EXACT command for debugging
            self.output_queue.put(("log", "━" * 60, "info"))
            self.output_queue.put(("log", "Executing command:", "info"))
            self.output_queue.put(("log", f"Script path (relative): {script_path}", "info"))
            self.output_queue.put(("log", f"Script path (absolute): {abs_script_path}", "info"))
            self.output_queue.put(("log", f"Full command: {' '.join(cmd)}", "info"))
            self.output_queue.put(("log", f"Inner command: {cmd_string}", "info"))
            self.output_queue.put(("log", "━" * 60, "info"))
            
            
            # Create process
            self.test_process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                creationflags=subprocess.CREATE_NO_WINDOW
            )
            
            self.output_queue.put(("log", "⚡ PowerShell process started", "success"))
            self.output_queue.put(("log", "   Waiting for UAC prompt and window launch...", "info"))
            
            # Wait for the launching process to complete
            try:
                stdout, stderr = self.test_process.communicate(timeout=10)
                
                self.output_queue.put(("log", "Process completed", "info"))
                if stdout:
                    self.output_queue.put(("log", f"STDOUT: {stdout}", "info"))
                if stderr:
                    self.output_queue.put(("log", f"STDERR: {stderr}", "error"))
                    
            except subprocess.TimeoutExpired:
                self.output_queue.put(("log", "⚠️ Process timeout - this may be normal", "warning"))
                self.test_process.kill()
                stdout, stderr = self.test_process.communicate()
            
            if self.test_process.returncode == 0:
                self.output_queue.put(("log", "✅ Test window launched successfully", "success"))
                self.output_queue.put(("status", "Test running in separate window"))
                
                # Wait for script to complete by monitoring log file
                import time
                self.output_queue.put(("log", "⏳ Waiting for test script to complete...", "info"))
                
                # Find the log file directory
                script_dir = Path(script_path).parent
                log_dir = script_dir.parent / "output" / "logs"
                
                # Wait up to 5 minutes for the log to be created and completed
                max_wait = 300  # 5 minutes
                check_interval = 2  # Check every 2 seconds
                elapsed = 0
                log_file_found = None
                
                while elapsed < max_wait:
                    if log_dir.exists():
                        log_files = sorted(log_dir.glob("*.log"), key=lambda p: p.stat().st_mtime, reverse=True)
                        if log_files:
                            log_file_found = log_files[0]
                            # Check if the log file contains completion marker
                            try:
                                with open(log_file_found, 'r', encoding='utf-8') as f:
                                    content = f.read()
                                    # Look for PowerShell transcript end marker or script end
                                    if "Windows PowerShell 脚本结束" in content or ("**********************" in content and content.count("**********************") >= 2):
                                        self.output_queue.put(("log", f"✅ Script completed, log file: {log_file_found.name}", "success"))
                                        break
                            except:
                                pass
                    
                    time.sleep(check_interval)
                    elapsed += check_interval
                    
                    # Show progress every 10 seconds
                    if elapsed % 10 == 0:
                        self.output_queue.put(("log", f"   Still waiting... ({elapsed}s elapsed)", "info"))
                
                if elapsed >= max_wait:
                    self.output_queue.put(("log", f"⚠️ Timeout waiting for script completion ({max_wait}s)", "warning"))
                
                # Additional 2 seconds to ensure file is fully written
                time.sleep(2)
                
                # Try to read and display results
                self._display_test_results(script_path)
            else:
                self.output_queue.put(("log", f"⚠️ Launch process exit code: {self.test_process.returncode}", "warning"))
                if stderr:
                    self.output_queue.put(("log", f"Error message:\n{stderr}", "error"))
            
            self.output_queue.put(("progress", 100))
            
            # Test execution completed - enable manual report generation
            self.output_queue.put(("log", "━" * 60, "info"))
            self.output_queue.put(("log", "✅ Test execution completed", "success"))
            self.output_queue.put(("log", "💡 Click [Generate Report] button to create HTML report with AI analysis", "info"))
            self.output_queue.put(("log", "━" * 60, "info"))
            
            # Always enable manual report generation button after test runs
            self.output_queue.put(("enable_gen_report", True))
            
        except Exception as e:
            self.output_queue.put(("log", f"❌ Execution failed: {str(e)}", "error"))
            import traceback
            self.output_queue.put(("log", traceback.format_exc(), "error"))
        finally:
            self.is_running = False
            self.output_queue.put(("enable_buttons", True))
    
    def _display_test_results(self, script_path):
        """Try to read and display test results from output directory"""
        try:
            # Find corresponding VerifyResult.json file
            script_name = Path(script_path).stem
            # Match case{id}_*_VerifyResult.json
            output_dir = Path(script_path).parent
            
            result_files = list(output_dir.glob("*_VerifyResult.json"))
            
            if result_files:
                # Find the latest result file
                latest_result = max(result_files, key=lambda p: p.stat().st_mtime)
                
                self.output_queue.put(("log", "━" * 60, "info"))
                self.output_queue.put(("log", "📊 Test Results Summary:", "info"))
                self.output_queue.put(("log", "━" * 60, "info"))
                
                with open(latest_result, 'r', encoding='utf-8') as f:
                    results = json.load(f)
                
                if isinstance(results, list):
                    pass_count = sum(1 for r in results if r.get('success'))
                    fail_count = len(results) - pass_count
                    
                    self.output_queue.put(("log", f"✅ Passed: {pass_count}", "pass"))
                    self.output_queue.put(("log", f"❌ Failed: {fail_count}", "fail"))
                    self.output_queue.put(("log", "━" * 60, "info"))
                    
                    # Display failed tests
                    if fail_count > 0:
                        self.output_queue.put(("log", "Failure Details:", "error"))
                        for r in results:
                            if not r.get('success'):
                                msg = r.get('message', 'Unknown')
                                self.output_queue.put(("log", f"  ❌ {msg}", "fail"))
                
                self.output_queue.put(("log", f"📄 Detailed results: {latest_result.name}", "info"))
                
        except Exception as e:
            self.output_queue.put(("log", f"⚠️ Unable to read test results: {str(e)}", "warning"))
    
    def stop_test(self):
        """Stop test execution"""
        if self.test_process and self.is_running:
            try:
                self.test_process.terminate()
                self.log_message("⏹️ Test stopped", "warning")
                self.status_var.set("Test stopped")
                self.is_running = False
                self._restore_button_states()
            except Exception as e:
                self.log_message(f"Stop failed: {str(e)}", "error")
    
    def _restore_button_states(self):
        """Restore button states after test completion"""
        # Enable generate button
        self.generate_btn.config(state='normal')
        
        # Enable run button only if there's a generated script
        if self.output_path.get() and Path(self.output_path.get()).exists():
            self.run_btn.config(state='normal')
        else:
            self.run_btn.config(state='disabled')
        
        # Enable run existing button only if a script is selected
        if self.existing_script_path.get() and Path(self.existing_script_path.get()).exists():
            self.run_existing_btn.config(state='normal')
        else:
            self.run_existing_btn.config(state='disabled')
        
        # Disable stop button
        self.stop_btn.config(state='disabled')
    
    def open_output_dir(self):
        """Open output directory"""
        output_dir = Path(__file__).parent / "output"
        output_dir.mkdir(exist_ok=True)
        
        os.startfile(str(output_dir))
    
    def view_report(self):
        """Open latest HTML report in browser"""
        if self.latest_report_path and Path(self.latest_report_path).exists():
            webbrowser.open(f"file:///{self.latest_report_path}")
            self.log_message(f"📊 Opening report: {Path(self.latest_report_path).name}", "info")
        else:
            messagebox.showwarning("No Report", "No report available. Please run a test first.")
    
    def generate_report_manually(self):
        """Manually generate HTML report from latest log file"""
        if not self.latest_script_path:
            messagebox.showwarning("No Script", "No test script has been executed yet.")
            return
        
        self.log_message("━" * 60, "info")
        self.log_message("📝 Manually generating HTML report...", "info")
        
        try:
            # Find the latest log file
            script_dir = Path(self.latest_script_path).parent
            log_dir = script_dir.parent / "output" / "logs"
            
            log_content = ""
            if log_dir.exists():
                log_files = sorted(log_dir.glob("*.log"), key=lambda p: p.stat().st_mtime, reverse=True)
                if log_files:
                    latest_log = log_files[0]
                    self.log_message(f"   Found log: {latest_log.name}", "info")
                    
                    with open(latest_log, 'r', encoding='utf-8') as f:
                        log_content = f.read()
                    
                    self.latest_log_file = str(latest_log)
            
            if not log_content:
                self.log_message("⚠️ No log file found", "warning")
                log_content = self.output_text.get(1.0, tk.END)
            
            # Generate HTML report with AI analysis
            report_gen = ReportGenerator()
            
            self.log_message("🤖 AI analyzing logs (this may take 10-30 seconds)...", "info")
            self.root.update()  # Force UI update
            
            ai_analysis = report_gen.analyze_logs_with_ai(
                logs=log_content,
                test_case_id=self.test_case_id.get() or Path(self.latest_script_path).stem
            )
            
            report_path = report_gen.generate_html_report(
                test_case_id=self.test_case_id.get() or Path(self.latest_script_path).stem,
                script_path=self.latest_script_path,
                logs=log_content,
                ai_analysis=ai_analysis,
                quality_evaluation=self.last_evaluation,
                timestamp=datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            )
            
            self.latest_report_path = report_path
            self.log_message(f"✅ HTML report generated: {Path(report_path).name}", "success")
            self.log_message(f"   Path: {report_path}", "info")
            
            # Enable view button
            self.view_report_btn.config(state='normal')
            
            # Ask if user wants to open it
            if messagebox.askyesno("Report Generated", "Report generated successfully! Open in browser?"):
                self.view_report()
                
        except Exception as e:
            self.log_message(f"❌ Report generation failed: {str(e)}", "error")
            import traceback
            self.log_message(traceback.format_exc(), "error")
    
    def clear_output(self):
        """Clear output log"""
        self.output_text.delete(1.0, tk.END)
        self.log_message("Log cleared", "info")
    
    def log_message(self, message, tag="info"):
        """Add log message"""
        timestamp = datetime.now().strftime("%H:%M:%S")
        
        self.output_text.insert(tk.END, f"[{timestamp}] ", "info")
        self.output_text.insert(tk.END, f"{message}\n", tag)
        self.output_text.see(tk.END)
    
    def check_output_queue(self):
        """Check output queue (for thread communication)"""
        try:
            while True:
                item = self.output_queue.get_nowait()
                
                if item[0] == "log":
                    self.log_message(item[1], item[2])
                elif item[0] == "status":
                    self.status_var.set(item[1])
                elif item[0] == "progress":
                    self.progress_var.set(item[1])
                elif item[0] == "enable_run":
                    self.run_btn.config(state='normal' if item[1] else 'disabled')
                elif item[0] == "enable_generate":
                    self.generate_btn.config(state='normal' if item[1] else 'disabled')
                elif item[0] == "enable_view_report":
                    self.view_report_btn.config(state='normal' if item[1] else 'disabled')
                elif item[0] == "enable_gen_report":
                    self.gen_report_btn.config(state='normal' if item[1] else 'disabled')
                elif item[0] == "enable_buttons":
                    self._restore_button_states()
                    
        except queue.Empty:
            pass
        
        # Check every 100ms
        self.root.after(100, self.check_output_queue)


def main():
    """Main function"""
    root = tk.Tk()
    
    # Set theme style
    style = ttk.Style()
    style.theme_use('vista')  # Windows style
    
    app = AutoTestGUI(root)
    root.mainloop()


if __name__ == '__main__':
    main()
