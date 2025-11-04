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

# Add current directory to path for imports
sys.path.insert(0, str(Path(__file__).parent))

try:
    from core.csv_parser import parse_csv_to_json, save_json
    from core.test_generator import TestScriptGenerator
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
        self.root.title("Auto-Test V2 - Automated Testing Client")
        self.root.geometry("900x700")
        self.root.minsize(800, 600)
        
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
        
        # Test process
        self.test_process = None
        self.is_running = False
        
        # Output queue (for thread communication)
        self.output_queue = queue.Queue()
        
        # Create UI
        self.create_widgets()
        
        # Start output monitoring
        self.check_output_queue()
    
    def create_widgets(self):
        """Create all UI widgets"""
        # Main frame
        main_frame = ttk.Frame(self.root, padding="10")
        main_frame.grid(row=0, column=0, sticky=(tk.W, tk.E, tk.N, tk.S))
        
        self.root.columnconfigure(0, weight=1)
        self.root.rowconfigure(0, weight=1)
        main_frame.columnconfigure(0, weight=1)
        main_frame.rowconfigure(3, weight=1)
        
        # ========== Title Area ==========
        title_frame = ttk.LabelFrame(main_frame, text="📋 Auto-Test V2", padding="10")
        title_frame.grid(row=0, column=0, sticky=(tk.W, tk.E), pady=(0, 10))
        
        ttk.Label(title_frame, text="Automated Test Script Generation & Execution Tool", 
                  font=('Arial', 10)).grid(row=0, column=0, sticky=tk.W)
        
        # ========== CSV File Selection Area ==========
        file_frame = ttk.LabelFrame(main_frame, text="🗂️ Step 1: Select CSV Test File", padding="10")
        file_frame.grid(row=1, column=0, sticky=(tk.W, tk.E), pady=(0, 10))
        file_frame.columnconfigure(1, weight=1)
        
        ttk.Label(file_frame, text="CSV File:").grid(row=0, column=0, sticky=tk.W, padx=(0, 5))
        ttk.Entry(file_frame, textvariable=self.csv_path, state='readonly').grid(
            row=0, column=1, sticky=(tk.W, tk.E), padx=(0, 5))
        ttk.Button(file_frame, text="Browse...", 
                   command=self.select_csv_file).grid(row=0, column=2)
        
        ttk.Label(file_frame, text="Test Case ID:").grid(row=1, column=0, sticky=tk.W, padx=(0, 5), pady=(5, 0))
        ttk.Entry(file_frame, textvariable=self.test_case_id).grid(
            row=1, column=1, sticky=(tk.W, tk.E), padx=(0, 5), pady=(5, 0))
        ttk.Label(file_frame, text="(optional)", foreground="gray").grid(
            row=1, column=2, sticky=tk.W, pady=(5, 0))
        
        # ========== Action Buttons Area ==========
        action_frame = ttk.LabelFrame(main_frame, text="⚙️ Step 2: Generate & Execute Test", padding="10")
        action_frame.grid(row=2, column=0, sticky=(tk.W, tk.E), pady=(0, 10))
        
        # Row 1: Generate Script
        btn_frame1 = ttk.Frame(action_frame)
        btn_frame1.grid(row=0, column=0, sticky=(tk.W, tk.E), pady=(0, 5))
        
        self.generate_btn = ttk.Button(btn_frame1, text="📝 Generate Script", 
                                       command=self.generate_script, width=20)
        self.generate_btn.grid(row=0, column=0, padx=(0, 10))
        
        self.run_btn = ttk.Button(btn_frame1, text="▶️ Run Generated Script", 
                                  command=self.run_test, width=20, state='disabled')
        self.run_btn.grid(row=0, column=1, padx=(0, 10))
        
        ttk.Button(btn_frame1, text="📂 Open Output Dir", 
                   command=self.open_output_dir, width=15).grid(row=0, column=2)
        
        # Row 2: Run Existing Script
        btn_frame2 = ttk.Frame(action_frame)
        btn_frame2.grid(row=1, column=0, sticky=(tk.W, tk.E), pady=(5, 0))
        
        ttk.Button(btn_frame2, text="📂 Select Existing Script", 
                   command=self.select_existing_script, width=20).grid(row=0, column=0, padx=(0, 10))
        
        self.run_existing_btn = ttk.Button(btn_frame2, text="▶️ Run Selected Script", 
                                           command=self.run_existing_test, width=20, state='disabled')
        self.run_existing_btn.grid(row=0, column=1, padx=(0, 10))
        
        self.stop_btn = ttk.Button(btn_frame2, text="⏹️ Stop Test", 
                                   command=self.stop_test, width=15, state='disabled')
        self.stop_btn.grid(row=0, column=2)
        
        # Progress bar
        ttk.Label(action_frame, text="Status:").grid(row=1, column=0, sticky=tk.W, pady=(10, 0))
        ttk.Label(action_frame, textvariable=self.status_var, 
                  foreground="blue").grid(row=2, column=0, sticky=tk.W)
        
        self.progress_bar = ttk.Progressbar(action_frame, mode='determinate', 
                                           variable=self.progress_var)
        self.progress_bar.grid(row=3, column=0, sticky=(tk.W, tk.E), pady=(5, 0))
        
        # ========== Output Log Area ==========
        output_frame = ttk.LabelFrame(main_frame, text="📊 Real-time Output Log", padding="10")
        output_frame.grid(row=3, column=0, sticky=(tk.W, tk.E, tk.N, tk.S))
        output_frame.columnconfigure(0, weight=1)
        output_frame.rowconfigure(0, weight=1)
        
        # Create scrolled text widget
        self.output_text = scrolledtext.ScrolledText(output_frame, wrap=tk.WORD, 
                                                      height=20, font=('Consolas', 9))
        self.output_text.grid(row=0, column=0, sticky=(tk.W, tk.E, tk.N, tk.S))
        
        # Configure text tag colors
        self.output_text.tag_config("success", foreground="green")
        self.output_text.tag_config("error", foreground="red")
        self.output_text.tag_config("warning", foreground="orange")
        self.output_text.tag_config("info", foreground="blue")
        self.output_text.tag_config("pass", foreground="green", font=('Consolas', 9, 'bold'))
        self.output_text.tag_config("fail", foreground="red", font=('Consolas', 9, 'bold'))
        
        # Clear log button
        ttk.Button(output_frame, text="Clear Log", 
                   command=self.clear_output).grid(row=1, column=0, sticky=tk.E, pady=(5, 0))
        
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
            
            self.output_queue.put(("progress", 100))
            self.output_queue.put(("log", f"✅ Test script generation completed!", "success"))
            self.output_queue.put(("log", f"📄 Output path: {output_path}", "success"))
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
                
                # Give user time to see the message
                import time
                time.sleep(2)
                
                # Try to read and display results after a delay
                self.output_queue.put(("log", "   Checking for test results...", "info"))
                time.sleep(3)  # Wait a bit for test to potentially complete
                self._display_test_results(script_path)
            else:
                self.output_queue.put(("log", f"⚠️ Launch process exit code: {self.test_process.returncode}", "warning"))
                if stderr:
                    self.output_queue.put(("log", f"Error message:\n{stderr}", "error"))
            
            self.output_queue.put(("progress", 100))
            
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
