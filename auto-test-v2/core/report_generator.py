"""
HTML Report Generator with AI Analysis
生成包含AI分析的HTML测试报告
"""
import os
from datetime import datetime
from pathlib import Path
from typing import Dict, Optional
from .model_client import ModelClient
from config.prompts import LOG_ANALYSIS_PROMPT


class ReportGenerator:
    """Generate HTML reports with AI analysis of test execution logs"""
    
    def __init__(self, model_client: Optional[ModelClient] = None):
        """
        Initialize report generator
        
        Args:
            model_client: Optional ModelClient instance. If None, will create new one.
        """
        self.model_client = model_client or ModelClient()
        
    def analyze_logs_with_ai(self, logs: str, test_case_id: str = "") -> str:
        """
        Send execution logs to AI for analysis and summary
        
        Args:
            logs: Test execution logs
            test_case_id: Test case identifier
            
        Returns:
            AI-generated analysis and summary
        """
        user_prompt = f"""Analyze these test execution logs:

TEST CASE: {test_case_id}

LOGS:
{logs[:4000]}

Provide a clear analysis in English."""

        try:
            analysis = self.model_client.generate(
                system_prompt=LOG_ANALYSIS_PROMPT,
                user_prompt=user_prompt,
                temperature=0.3,
                max_tokens=2000
            )
            return analysis
        except Exception as e:
            return f"⚠️ AI分析失败: {str(e)}\n\n请手动查看日志。"
    
    def generate_html_report(
        self,
        test_case_id: str,
        script_path: str,
        logs: str,
        ai_analysis: str = "",
        timestamp: str = "",
        validation_report: str = "",
        quality_evaluation: Dict = None
    ) -> str:
        """
        Generate HTML report with logs and AI analysis
        
        Args:
            test_case_id: Test case ID
            script_path: Path to executed script
            logs: Execution logs
            ai_analysis: AI-generated analysis (optional)
            timestamp: Execution timestamp (optional)
            validation_report: Script validation results (optional)
            quality_evaluation: AI quality evaluation results (optional)
            
        Returns:
            Path to generated HTML file
        """
        if not timestamp:
            timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        
        # Determine overall status from logs
        status = "PASS" if "[FAIL]" not in logs and "ERROR" not in logs.upper() else "FAIL"
        status_color = "#28a745" if status == "PASS" else "#dc3545"
        
        # Count pass/fail
        pass_count = logs.count("[PASS]")
        fail_count = logs.count("[FAIL]")
        
        # Escape HTML special characters
        logs_escaped = logs.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
        ai_analysis_escaped = ai_analysis.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
        validation_escaped = validation_report.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
        
        html_content = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Test Execution Report - {test_case_id}</title>
    <style>
        * {{
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }}
        
        body {{
            font-family: 'Segoe UI', 'Microsoft YaHei', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            padding: 20px;
            min-height: 100vh;
        }}
        
        .container {{
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            border-radius: 12px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.2);
            overflow: hidden;
        }}
        
        .header {{
            background: linear-gradient(135deg, #5e72e4 0%, #825ee4 100%);
            color: white;
            padding: 30px;
            text-align: center;
        }}
        
        .header h1 {{
            font-size: 2em;
            margin-bottom: 10px;
        }}
        
        .header .test-id {{
            font-size: 1.2em;
            opacity: 0.9;
        }}
        
        .status-badge {{
            display: inline-block;
            padding: 8px 20px;
            border-radius: 20px;
            background: {status_color};
            color: white;
            font-weight: bold;
            font-size: 1.1em;
            margin-top: 15px;
        }}
        
        .summary {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            padding: 30px;
            background: #f8f9fa;
        }}
        
        .summary-card {{
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.1);
            text-align: center;
        }}
        
        .summary-card h3 {{
            color: #666;
            font-size: 0.9em;
            margin-bottom: 10px;
            text-transform: uppercase;
        }}
        
        .summary-card .value {{
            font-size: 2em;
            font-weight: bold;
            color: #333;
        }}
        
        .summary-card.pass .value {{
            color: #28a745;
        }}
        
        .summary-card.fail .value {{
            color: #dc3545;
        }}
        
        .content {{
            padding: 30px;
        }}
        
        .section {{
            margin-bottom: 30px;
        }}
        
        .section-title {{
            font-size: 1.5em;
            color: #333;
            margin-bottom: 15px;
            padding-bottom: 10px;
            border-bottom: 3px solid #5e72e4;
            display: flex;
            align-items: center;
            gap: 10px;
        }}
        
        .section-title::before {{
            content: "";
            display: inline-block;
            width: 6px;
            height: 30px;
            background: #5e72e4;
            border-radius: 3px;
        }}
        
        .code-block {{
            background: #1e1e1e;
            color: #d4d4d4;
            padding: 20px;
            border-radius: 8px;
            font-family: 'Consolas', 'Courier New', monospace;
            font-size: 0.9em;
            line-height: 1.6;
            overflow-x: auto;
            white-space: pre-wrap;
            word-wrap: break-word;
            max-height: 600px;
            overflow-y: auto;
        }}
        
        .analysis-block {{
            background: #fff3cd;
            border-left: 4px solid #ffc107;
            padding: 20px;
            border-radius: 8px;
            color: #856404;
            line-height: 1.8;
            white-space: pre-wrap;
        }}
        
        .validation-block {{
            background: #d1ecf1;
            border-left: 4px solid #0c5460;
            padding: 20px;
            border-radius: 8px;
            color: #0c5460;
            line-height: 1.8;
            white-space: pre-wrap;
        }}
        
        .quality-section {{
            background: #fff3cd;
            border: 2px solid #ffc107;
            border-radius: 12px;
            padding: 25px;
            margin: 20px 0;
        }}
        
        .quality-score-card {{
            text-align: center;
            padding: 30px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border-radius: 12px;
            margin-bottom: 20px;
        }}
        
        .quality-score-value {{
            font-size: 4em;
            font-weight: bold;
            margin: 10px 0;
        }}
        
        .quality-score-grade {{
            font-size: 2em;
            font-weight: bold;
            opacity: 0.9;
        }}
        
        .quality-dimensions {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin: 20px 0;
        }}
        
        .dimension-card {{
            background: white;
            padding: 15px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }}
        
        .dimension-name {{
            font-weight: bold;
            color: #495057;
            margin-bottom: 5px;
        }}
        
        .dimension-score {{
            font-size: 2em;
            font-weight: bold;
            color: #5e72e4;
        }}
        
        .quality-list {{
            margin: 15px 0;
        }}
        
        .quality-list h4 {{
            margin: 10px 0;
            color: #495057;
        }}
        
        .quality-list ul {{
            list-style-type: none;
            padding-left: 0;
        }}
        
        .quality-list li {{
            padding: 8px 0;
            border-bottom: 1px solid #e9ecef;
        }}
        
        .quality-list li:before {{
            content: "• ";
            color: #5e72e4;
            font-weight: bold;
            display: inline-block;
            width: 1em;
        }}
        
        .grade-badge {{
            font-size: 2.5em;
            font-weight: bold;
            padding: 0.2em 0.5em;
            border-radius: 8px;
            margin-top: 0.5em;
        }}
        
        .grade-a {{
            background: linear-gradient(135deg, #28a745 0%, #20c997 100%);
            color: white;
        }}
        
        .grade-b {{
            background: linear-gradient(135deg, #17a2b8 0%, #3498db 100%);
            color: white;
        }}
        
        .grade-c {{
            background: linear-gradient(135deg, #ffc107 0%, #ff9800 100%);
            color: white;
        }}
        
        .grade-d {{
            background: linear-gradient(135deg, #ff9800 0%, #ff5722 100%);
            color: white;
        }}
        
        .grade-f {{
            background: linear-gradient(135deg, #dc3545 0%, #c82333 100%);
            color: white;
        }}
        
        .footer {{
            background: #f8f9fa;
            padding: 20px;
            text-align: center;
            color: #666;
            font-size: 0.9em;
        }}
        
        .collapsible {{
            cursor: pointer;
            user-select: none;
        }}
        
        .collapsible:hover {{
            opacity: 0.8;
        }}
        
        .collapsible::after {{
            content: " [Click to Expand]";
            font-size: 0.8em;
            color: #5e72e4;
        }}
        
        .collapsible.active::after {{
            content: " [Click to Collapse]";
        }}
        
        .collapsed {{
            max-height: 200px;
            overflow: hidden;
            position: relative;
        }}
        
        .collapsed::after {{
            content: "";
            position: absolute;
            bottom: 0;
            left: 0;
            right: 0;
            height: 80px;
            background: linear-gradient(transparent, #1e1e1e);
            pointer-events: none;
        }}
        
        /* Syntax highlighting for logs */
        .log-pass {{ color: #4ec9b0; font-weight: bold; }}
        .log-fail {{ color: #f48771; font-weight: bold; }}
        .log-info {{ color: #9cdcfe; }}
        .log-warn {{ color: #dcdcaa; }}
    </style>
    <script>
        function toggleCollapse(element) {{
            const content = element.nextElementSibling;
            element.classList.toggle('active');
            content.classList.toggle('collapsed');
        }}
        
        // Highlight log keywords
        window.onload = function() {{
            const logBlock = document.getElementById('logs');
            if (logBlock) {{
                let html = logBlock.innerHTML;
                html = html.replace(/\[PASS\]/g, '<span class="log-pass">[PASS]</span>');
                html = html.replace(/\[FAIL\]/g, '<span class="log-fail">[FAIL]</span>');
                html = html.replace(/\[INFO\]/g, '<span class="log-info">[INFO]</span>');
                html = html.replace(/\[WARN\]/g, '<span class="log-warn">[WARN]</span>');
                logBlock.innerHTML = html;
            }}
        }};
    </script>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🧪 Test Execution Report</h1>
            <div class="test-id">Test Case: {test_case_id}</div>
            <div class="status-badge">{status}</div>
        </div>
        
        <div class="summary">
            <div class="summary-card">
                <h3>Execution Time</h3>
                <div class="value" style="font-size: 1.2em;">{timestamp}</div>
            </div>
            <div class="summary-card pass">
                <h3>Passed Checks</h3>
                <div class="value">{pass_count}</div>
            </div>
            <div class="summary-card fail">
                <h3>Failed Checks</h3>
                <div class="value">{fail_count}</div>
            </div>
            <div class="summary-card">
                <h3>Test Script</h3>
                <div class="value" style="font-size: 0.9em; word-break: break-all;">{os.path.basename(script_path)}</div>
            </div>
        </div>
        
        <div class="content">
            {f'''
            <div class="section">
                <h2 class="section-title">📋 Script Validation Results</h2>
                <div class="validation-block">{validation_escaped if validation_escaped else "✓ Script passed all validation checks"}</div>
            </div>
            ''' if validation_report else ''}
            
            {f'''
            <div class="section quality-section">
                <h2 class="section-title">⭐ AI Quality Evaluation</h2>
                <div class="quality-score-card">
                    <div class="score-label">Overall Quality Score</div>
                    <div class="score-value">{quality_evaluation.get("overall_score", 0)}</div>
                    <div class="grade-badge grade-{quality_evaluation.get("grade", "F").lower()}">{quality_evaluation.get("grade", "N/A")}</div>
                </div>
                
                <h3 style="margin-top: 2em; color: #333;">Dimension Scores</h3>
                <div class="quality-dimensions">
                    <div class="dimension-card">
                        <div class="dimension-name">Correctness</div>
                        <div class="dimension-score">{quality_evaluation.get("scores", {}).get("correctness", 0)}/100</div>
                        <div class="dimension-weight">Weight: 30%</div>
                    </div>
                    <div class="dimension-card">
                        <div class="dimension-name">Completeness</div>
                        <div class="dimension-score">{quality_evaluation.get("scores", {}).get("completeness", 0)}/100</div>
                        <div class="dimension-weight">Weight: 25%</div>
                    </div>
                    <div class="dimension-card">
                        <div class="dimension-name">Best Practices</div>
                        <div class="dimension-score">{quality_evaluation.get("scores", {}).get("best_practices", 0)}/100</div>
                        <div class="dimension-weight">Weight: 15%</div>
                    </div>
                    <div class="dimension-card">
                        <div class="dimension-name">Robustness</div>
                        <div class="dimension-score">{quality_evaluation.get("scores", {}).get("robustness", 0)}/100</div>
                        <div class="dimension-weight">Weight: 20%</div>
                    </div>
                    <div class="dimension-card">
                        <div class="dimension-name">Maintainability</div>
                        <div class="dimension-score">{quality_evaluation.get("scores", {}).get("maintainability", 0)}/100</div>
                        <div class="dimension-weight">Weight: 10%</div>
                    </div>
                </div>
                
                <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 2em; margin-top: 2em;">
                    <div>
                        <h3 style="color: #28a745;">✅ Strengths</h3>
                        <ul class="quality-list">
                            {"".join(f"<li>{item}</li>" for item in quality_evaluation.get("strengths", [])[:5])}
                        </ul>
                    </div>
                    <div>
                        <h3 style="color: #dc3545;">⚠️ Areas for Improvement</h3>
                        <ul class="quality-list">
                            {"".join(f"<li>{item}</li>" for item in quality_evaluation.get("weaknesses", [])[:5])}
                        </ul>
                    </div>
                </div>
                
                {f'<div style="margin-top: 2em; padding: 1em; background: #f8f9fa; border-left: 4px solid #007bff; border-radius: 4px;"><h3 style="margin-top: 0; color: #007bff;">💡 Recommendations</h3><ul class="quality-list">{"".join(f"<li>{item}</li>" for item in quality_evaluation.get("recommendations", []))}</ul></div>' if quality_evaluation.get("recommendations") else ''}
            </div>
            ''' if quality_evaluation else ''}
            
            {f'''
            <div class="section">
                <h2 class="section-title">🤖 AI Analysis</h2>
                <div class="analysis-block">{ai_analysis_escaped}</div>
            </div>
            ''' if ai_analysis else ''}
            
            <div class="section">
                <h2 class="section-title collapsible" onclick="toggleCollapse(this)">📜 Full Execution Log</h2>
                <div class="code-block collapsed" id="logs">{logs_escaped}</div>
            </div>
        </div>
        
        <div class="footer">
            <p>Generated by Auto-Test-v2 | {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}</p>
            <p>Script: {script_path}</p>
        </div>
    </div>
</body>
</html>
"""
        
        # Save HTML report
        output_dir = Path(__file__).parent.parent / "output" / "reports"
        output_dir.mkdir(parents=True, exist_ok=True)
        
        report_filename = f"report_{test_case_id}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.html"
        report_path = output_dir / report_filename
        
        with open(report_path, "w", encoding="utf-8") as f:
            f.write(html_content)
        
        return str(report_path)
