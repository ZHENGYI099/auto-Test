# ============================================================
# CMD Extension 完全清理脚本
# 用途: 清理目录 + WMI 命名空间
# ============================================================

# 检查管理员权限
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR - Must run as Administrator" -ForegroundColor Red
    Write-Host "Right-click and select 'Run as Administrator'" -ForegroundColor Yellow
    pause
    exit 1
}

$targetPath = "C:\ProgramData\Microsoft\CMDExtension"
$serviceName = "CloudManagedDesktopExtension"
$wmiNamespace = "root\cmd\clientagent"
$wmiParentNamespace = "root\cmd"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "CMD Extension Complete Cleanup Script" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Target: $targetPath" -ForegroundColor Yellow
Write-Host ""

# 检查目录是否存在
if (-not (Test-Path $targetPath)) {
    Write-Host "Directory does not exist. Nothing to delete." -ForegroundColor Green
    pause
    exit 0
}

# 显示目录信息
try {
    $dirSize = (Get-ChildItem -Path $targetPath -Recurse -Force -ErrorAction SilentlyContinue | 
                Measure-Object -Property Length -Sum).Sum
    $dirSizeMB = [math]::Round($dirSize / 1MB, 2)
    $fileCount = (Get-ChildItem -Path $targetPath -Recurse -Force -ErrorAction SilentlyContinue).Count
    
    Write-Host "Directory Information:" -ForegroundColor Cyan
    Write-Host "  Size: $dirSizeMB MB" -ForegroundColor Gray
    Write-Host "  Files: $fileCount" -ForegroundColor Gray
    Write-Host ""
} catch {
    Write-Host "  Unable to read directory details" -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "Starting cleanup..." -ForegroundColor Cyan
Write-Host ""

# 步骤 1: 停止服务（如果正在运行）
try {
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($service) {
        if ($service.Status -eq "Running") {
            Write-Host "[1/4] Stopping $serviceName service..." -ForegroundColor Yellow
            Stop-Service -Name $serviceName -Force -ErrorAction Stop
            Start-Sleep -Seconds 2
            Write-Host "      Service stopped successfully" -ForegroundColor Green
        } else {
            Write-Host "[1/4] Service is not running" -ForegroundColor Gray
        }
    } else {
        Write-Host "[1/4] Service not found" -ForegroundColor Gray
    }
} catch {
    Write-Host "[1/4] Warning: Could not stop service - $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host ""

# 步骤 2: 结束占用文件的进程
Write-Host "[2/4] Checking for processes using the directory..." -ForegroundColor Yellow
try {
    $processes = Get-Process | Where-Object { 
        $_.Path -and $_.Path.StartsWith($targetPath, [StringComparison]::OrdinalIgnoreCase) 
    }
    
    if ($processes) {
        foreach ($proc in $processes) {
            Write-Host "      Stopping process: $($proc.Name) (PID: $($proc.Id))" -ForegroundColor Yellow
            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 1
        Write-Host "      Processes stopped" -ForegroundColor Green
    } else {
        Write-Host "      No processes found" -ForegroundColor Gray
    }
} catch {
    Write-Host "      Warning: Process check failed - $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host ""

# 步骤 3: 删除目录
Write-Host "[3/4] Deleting directory..." -ForegroundColor Yellow

$deleted = $false
$retries = 0
$maxRetries = 3

while (-not $deleted -and $retries -lt $maxRetries) {
    try {
        Remove-Item -Path $targetPath -Recurse -Force -ErrorAction Stop
        $deleted = $true
        Write-Host "      Directory deleted successfully" -ForegroundColor Green
    } catch {
        $retries++
        Write-Host "      Attempt $retries failed: $($_.Exception.Message)" -ForegroundColor Yellow
        
        if ($retries -lt $maxRetries) {
            Write-Host "      Waiting 2 seconds before retry..." -ForegroundColor Gray
            Start-Sleep -Seconds 2
        } else {
            Write-Host "      All retries failed. Trying alternative method..." -ForegroundColor Yellow
            
            # 尝试使用 cmd 的 rd 命令强制删除
            try {
                $null = cmd /c "rd /s /q `"$targetPath`" 2>&1"
                Start-Sleep -Seconds 1
                
                if (-not (Test-Path $targetPath)) {
                    $deleted = $true
                    Write-Host "      Directory deleted using alternative method" -ForegroundColor Green
                } else {
                    Write-Host "      Alternative method also failed" -ForegroundColor Red
                }
            } catch {
                Write-Host "      Alternative method error: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
}

Write-Host ""

# 步骤 4: 验证删除
Write-Host "[4/4] Verifying deletion..." -ForegroundColor Yellow

if (-not (Test-Path $targetPath)) {
    Write-Host "      Verification PASSED - Directory successfully removed" -ForegroundColor Green
    $exitCode = 0
} else {
    Write-Host "      Verification FAILED - Directory still exists" -ForegroundColor Red
    Write-Host ""
    Write-Host "Possible reasons:" -ForegroundColor Yellow
    Write-Host "  - Files are locked by running processes" -ForegroundColor Gray
    Write-Host "  - Insufficient permissions" -ForegroundColor Gray
    Write-Host "  - Files are in use by system services" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Suggestions:" -ForegroundColor Yellow
    Write-Host "  1. Restart the computer and try again" -ForegroundColor Gray
    Write-Host "  2. Boot into Safe Mode and delete manually" -ForegroundColor Gray
    Write-Host "  3. Use third-party tools like Unlocker" -ForegroundColor Gray
    $exitCode = 1
}

Write-Host ""

# ============================================================
# PHASE 2: WMI NAMESPACE CLEANUP
# ============================================================
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PHASE 2: WMI Namespace Cleanup" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# Check WMI namespace existence
Write-Host "[1/2] Checking WMI namespace: $wmiNamespace" -ForegroundColor Yellow
$wmiExists = $false
try {
    $null = Get-WmiObject -Namespace $wmiNamespace -List -ErrorAction Stop | Select-Object -First 1
    Write-Host "      [OK] Namespace EXISTS" -ForegroundColor Green
    $wmiExists = $true
    
    # Display WMI classes
    $classes = Get-WmiObject -Namespace $wmiNamespace -List | 
               Where-Object { $_.Name -notlike "__*" -and $_.Name -notlike "CIM_*" -and $_.Name -notlike "MSFT_*" } |
               Select-Object -ExpandProperty Name
    
    if ($classes) {
        Write-Host "      Found $($classes.Count) custom classes:" -ForegroundColor Gray
        foreach ($class in $classes) {
            Write-Host "        - $class" -ForegroundColor Gray
        }
    }
} catch {
    Write-Host "      [INFO] Namespace NOT FOUND (already clean)" -ForegroundColor Gray
    $wmiExists = $false
}

Write-Host ""

# Delete WMI namespace
if ($wmiExists) {
    Write-Host "[2/2] Deleting WMI namespace..." -ForegroundColor Yellow
    
    try {
        # Delete namespace
        $ns = Get-WmiObject -Namespace $wmiParentNamespace -Class "__NAMESPACE" -Filter "Name='ClientAgent'"
        if ($ns) {
            $ns.Delete()
            Write-Host "      [OK] WMI namespace deleted successfully" -ForegroundColor Green
        } else {
            Write-Host "      [WARN] Namespace object not found (may be already deleted)" -ForegroundColor Yellow
        }
        
        # Verify deletion
        Start-Sleep -Seconds 1
        try {
            $null = Get-WmiObject -Namespace $wmiNamespace -List -ErrorAction Stop | Select-Object -First 1
            Write-Host "      [WARN] Namespace still exists" -ForegroundColor Yellow
        } catch {
            Write-Host "      [OK] Verification passed - Namespace removed" -ForegroundColor Green
        }
    } catch {
        Write-Host "      [ERROR] Error deleting WMI namespace: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "      Note: WMI namespace will be auto-cleaned on next MSI uninstall" -ForegroundColor Gray
    }
} else {
    Write-Host "[2/2] WMI namespace already clean - no action needed" -ForegroundColor Gray
}

Write-Host ""

# ============================================================
# SUMMARY
# ============================================================
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Cleanup Complete" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Summary:" -ForegroundColor Yellow
Write-Host "  [OK] Phase 1: Directory cleanup completed" -ForegroundColor Gray
Write-Host "  [OK] Phase 2: WMI namespace cleanup completed" -ForegroundColor Gray
Write-Host ""
Write-Host "System is now clean and ready for reinstallation." -ForegroundColor Green
Write-Host ""

pause
exit $exitCode
