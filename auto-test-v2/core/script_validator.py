"""
PowerShell Script Validator
验证生成的 PowerShell 脚本是否符合规范
"""
import re
from typing import Dict, List


class ScriptValidator:
    """Validate generated PowerShell scripts for common issues"""
    
    def __init__(self):
        self.issues: List[Dict[str, str]] = []
        self.warnings: List[Dict[str, str]] = []
        
    def validate_script(self, script: str) -> Dict[str, any]:
        """
        Validate PowerShell script for common issues
        
        Args:
            script: PowerShell script content
            
        Returns:
            Dict with validation results
        """
        self.issues = []
        self.warnings = []
        
        # Run all validation checks
        self._check_admin_elevation(script)
        self._check_error_handling(script)
        self._check_logging(script)
        self._check_exit_codes(script)
        self._check_silent_install(script)
        self._check_forbidden_syntax(script)
        self._check_script_completeness(script)
        self._check_string_comparison(script)
        
        return {
            "is_valid": len(self.issues) == 0,
            "issues": self.issues,
            "warnings": self.warnings,
            "issue_count": len(self.issues),
            "warning_count": len(self.warnings)
        }
    
    def _check_admin_elevation(self, script: str):
        """Check for admin privilege verification"""
        if "IsInRole" not in script or "Administrator" not in script:
            self.warnings.append({
                "type": "missing_admin_check",
                "message": "脚本可能缺少管理员权限检查"
            })
    
    def _check_error_handling(self, script: str):
        """Check for try-catch blocks"""
        try_count = script.count("try {")
        catch_count = script.count("catch {")
        
        if try_count == 0:
            self.warnings.append({
                "type": "no_error_handling",
                "message": "脚本没有错误处理 (try-catch)"
            })
        elif try_count != catch_count:
            self.issues.append({
                "type": "unbalanced_try_catch",
                "message": f"try-catch 不匹配: {try_count} try, {catch_count} catch"
            })
    
    def _check_logging(self, script: str):
        """Check for transcript logging"""
        if "Start-Transcript" not in script:
            self.warnings.append({
                "type": "no_transcript",
                "message": "脚本没有启用 PowerShell transcript 日志"
            })
        
        if "Start-Transcript" in script and "Stop-Transcript" not in script:
            self.issues.append({
                "type": "unclosed_transcript",
                "message": "Start-Transcript 没有对应的 Stop-Transcript"
            })
    
    def _check_exit_codes(self, script: str):
        """Check for exit code validation"""
        if "msiexec" in script.lower() or ".msi" in script.lower():
            if "$LASTEXITCODE" not in script and "$exitCode" not in script:
                self.warnings.append({
                    "type": "no_exit_code_check",
                    "message": "MSI 安装后没有检查退出代码"
                })
    
    def _check_silent_install(self, script: str):
        """Check for silent installation flags"""
        if "/qn+" in script:
            self.issues.append({
                "type": "non_silent_install",
                "message": "使用了 /qn+ (显示完成对话框), 应使用 /qn 完全静默安装"
            })
        
        if re.search(r'Start-Process.*explorer\.exe', script, re.IGNORECASE):
            self.issues.append({
                "type": "gui_automation",
                "message": "脚本使用了 GUI 工具 (explorer.exe), 应使用 PowerShell 命令"
            })
    
    def _check_forbidden_syntax(self, script: str):
        """Check for forbidden PowerShell syntax"""
        # Check for goto statements
        if re.search(r'\bgoto\b', script, re.IGNORECASE):
            self.issues.append({
                "type": "forbidden_goto",
                "message": "PowerShell 不支持 goto 语句"
            })
        
        # Check for label syntax
        if re.search(r':[A-Za-z_]\w*\s*$', script, re.MULTILINE):
            self.issues.append({
                "type": "forbidden_label",
                "message": "发现标签语法 (:label), PowerShell 不支持"
            })
        
        # Check for Service.Status.Trim() bug
        if ".Status.Trim()" in script:
            self.issues.append({
                "type": "enum_trim_bug",
                "message": "严重错误: Service.Status 是枚举类型, 不能使用 .Trim()"
            })
    
    def _check_script_completeness(self, script: str):
        """Check if script is complete"""
        lines = script.strip().split('\n')
        
        # Check for summary section
        if "TEST EXECUTION SUMMARY" not in script:
            self.warnings.append({
                "type": "no_summary",
                "message": "脚本缺少执行摘要部分"
            })
        
        # Check for proper ending
        if "Stop-Transcript" not in script:
            self.warnings.append({
                "type": "missing_stop_transcript",
                "message": "脚本缺少 Stop-Transcript"
            })
        
        # Check for unclosed strings or braces
        open_braces = script.count('{')
        close_braces = script.count('}')
        if open_braces != close_braces:
            self.issues.append({
                "type": "unbalanced_braces",
                "message": f"花括号不匹配: {open_braces} 个 '{{', {close_braces} 个 '}}'"
            })
    
    def _check_string_comparison(self, script: str):
        """Check for proper string trimming in comparisons"""
        # Look for direct registry/file comparisons without trimming
        patterns = [
            (r'\$\w+\s*=\s*Get-ItemProperty.*\n.*-eq\s+["\']', 
             "注册表值比较前可能需要 Trim()"),
            (r'\$\w+\s*=\s*Get-Content.*\n.*-eq\s+["\']', 
             "文件内容比较前可能需要 Trim()"),
        ]
        
        for pattern, message in patterns:
            if re.search(pattern, script, re.MULTILINE):
                self.warnings.append({
                    "type": "potential_string_compare",
                    "message": message
                })
    
    def get_validation_report(self) -> str:
        """
        Get human-readable validation report
        
        Returns:
            Formatted validation report
        """
        if len(self.issues) == 0 and len(self.warnings) == 0:
            return "✓ 脚本验证通过，没有发现问题"
        
        report_lines = []
        
        if self.issues:
            report_lines.append(f"❌ 发现 {len(self.issues)} 个错误:\n")
            for i, issue in enumerate(self.issues, 1):
                report_lines.append(f"{i}. [{issue['type']}] {issue['message']}")
            report_lines.append("")
        
        if self.warnings:
            report_lines.append(f"⚠️ 发现 {len(self.warnings)} 个警告:\n")
            for i, warning in enumerate(self.warnings, 1):
                report_lines.append(f"{i}. [{warning['type']}] {warning['message']}")
        
        return "\n".join(report_lines)
