# ============================================================
# CMDExtension 完全清理脚本
# 功能: 安全删除 C:\ProgramData\Microsoft\CMDExtension 目录
# ============================================================

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "CMDExtension 完全清理脚本" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# 检查管理员权限
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[ERROR] 必须以管理员身份运行此脚本！" -ForegroundColor Red
    Write-Host "请右键点击脚本，选择 '以管理员身份运行'" -ForegroundColor Yellow
    pause
    exit 1
}

$targetPath = "C:\ProgramData\Microsoft\CMDExtension"

# 检查目录是否存在
if (-not (Test-Path $targetPath)) {
    Write-Host "[INFO] 目录不存在: $targetPath" -ForegroundColor Yellow
    Write-Host "[INFO] 无需清理，已经是干净状态" -ForegroundColor Green
    pause
    exit 0
}

Write-Host "[INFO] 发现 CMDExtension 目录" -ForegroundColor Yellow
Write-Host "路径: $targetPath" -ForegroundColor Gray

# 显示目录大小
try {
    $size = (Get-ChildItem -Path $targetPath -Recurse -File -ErrorAction SilentlyContinue | 
             Measure-Object -Property Length -Sum).Sum
    $sizeMB = [math]::Round($size / 1MB, 2)
    Write-Host "大小: $sizeMB MB" -ForegroundColor Gray
} catch {
    Write-Host "无法计算目录大小（可能包含受保护文件）" -ForegroundColor Gray
}

# 列出子目录
Write-Host "`n包含以下内容:" -ForegroundColor Yellow
try {
    Get-ChildItem -Path $targetPath -Directory -ErrorAction SilentlyContinue | 
        ForEach-Object { Write-Host "  [DIR]  $($_.Name)" -ForegroundColor Cyan }
    Get-ChildItem -Path $targetPath -File -ErrorAction SilentlyContinue | 
        ForEach-Object { Write-Host "  [FILE] $($_.Name)" -ForegroundColor Gray }
} catch {
    Write-Host "  无法列出内容（权限限制）" -ForegroundColor Gray
}

# 确认删除
Write-Host "`n" -NoNewline
Write-Host "[警告] 即将删除整个 CMDExtension 目录！" -ForegroundColor Red
Write-Host "[警告] 此操作不可恢复！" -ForegroundColor Red
Write-Host ""
$confirmation = Read-Host "确认删除? (输入 YES 继续，其他键取消)"

if ($confirmation -ne "YES") {
    Write-Host "`n[取消] 用户取消操作" -ForegroundColor Yellow
    pause
    exit 0
}

Write-Host ""
Write-Host "开始清理..." -ForegroundColor Cyan

# 步骤 1: 停止相关服务
Write-Host "[1/4] 检查并停止 CloudManagedDesktopExtension 服务..." -ForegroundColor Yellow
$service = Get-Service -Name "CloudManagedDesktopExtension" -ErrorAction SilentlyContinue
if ($service) {
    if ($service.Status -eq "Running") {
        Write-Host "  正在停止服务..." -ForegroundColor Gray
        try {
            Stop-Service -Name "CloudManagedDesktopExtension" -Force -ErrorAction Stop
            Start-Sleep -Seconds 2
            Write-Host "  [成功] 服务已停止" -ForegroundColor Green
        } catch {
            Write-Host "  [警告] 无法停止服务: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "  将尝试强制删除文件..." -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [信息] 服务未运行" -ForegroundColor Gray
    }
} else {
    Write-Host "  [信息] 服务不存在" -ForegroundColor Gray
}

# 步骤 2: 结束占用进程
Write-Host "[2/4] 检查并结束占用进程..." -ForegroundColor Yellow
$processes = Get-Process | Where-Object { 
    $_.Path -and $_.Path.StartsWith($targetPath, [StringComparison]::OrdinalIgnoreCase)
}

if ($processes) {
    Write-Host "  发现 $($processes.Count) 个进程占用目录:" -ForegroundColor Gray
    foreach ($proc in $processes) {
        Write-Host "    - $($proc.ProcessName) (PID: $($proc.Id))" -ForegroundColor Gray
        try {
            $proc.Kill()
            $proc.WaitForExit(5000)
            Write-Host "      已结束" -ForegroundColor Green
        } catch {
            Write-Host "      [警告] 无法结束进程: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "  [信息] 没有进程占用此目录" -ForegroundColor Gray
}

# 步骤 3: 删除目录
Write-Host "[3/4] 删除目录及所有内容..." -ForegroundColor Yellow

try {
    # 尝试移除只读属性
    Write-Host "  移除只读/隐藏属性..." -ForegroundColor Gray
    Get-ChildItem -Path $targetPath -Recurse -Force -ErrorAction SilentlyContinue | 
        ForEach-Object {
            try {
                $_.Attributes = 'Normal'
            } catch {}
        }
    
    # 删除目录
    Write-Host "  正在删除..." -ForegroundColor Gray
    Remove-Item -Path $targetPath -Recurse -Force -ErrorAction Stop
    
    Write-Host "  [成功] 目录已删除" -ForegroundColor Green
    
} catch {
    Write-Host "  [错误] 删除失败: $($_.Exception.Message)" -ForegroundColor Red
    
    # 尝试使用 cmd 的 rd 命令（有时更强力）
    Write-Host "  尝试使用系统命令强制删除..." -ForegroundColor Yellow
    try {
        cmd /c "rd /s /q `"$targetPath`"" 2>$null
        Start-Sleep -Seconds 2
        
        if (-not (Test-Path $targetPath)) {
            Write-Host "  [成功] 使用系统命令删除成功" -ForegroundColor Green
        } else {
            Write-Host "  [失败] 仍然无法删除" -ForegroundColor Red
            Write-Host "`n可能的原因:" -ForegroundColor Yellow
            Write-Host "  1. 文件被其他进程占用" -ForegroundColor Gray
            Write-Host "  2. 权限不足（即使是管理员）" -ForegroundColor Gray
            Write-Host "  3. 系统服务正在使用" -ForegroundColor Gray
            Write-Host "`n建议:" -ForegroundColor Yellow
            Write-Host "  1. 重启计算机后重试" -ForegroundColor Gray
            Write-Host "  2. 使用 Process Explorer 检查占用进程" -ForegroundColor Gray
            Write-Host "  3. 在安全模式下删除" -ForegroundColor Gray
        }
    } catch {
        Write-Host "  [失败] 系统命令也无法删除" -ForegroundColor Red
    }
}

# 步骤 4: 验证删除结果
Write-Host "[4/4] 验证删除结果..." -ForegroundColor Yellow

if (Test-Path $targetPath) {
    Write-Host "  [失败] 目录仍然存在" -ForegroundColor Red
    
    # 显示剩余内容
    Write-Host "`n剩余内容:" -ForegroundColor Yellow
    try {
        Get-ChildItem -Path $targetPath -Recurse -Force -ErrorAction SilentlyContinue | 
            Select-Object -First 20 | 
            ForEach-Object {
                $relativePath = $_.FullName.Replace($targetPath, "")
                if ($_.PSIsContainer) {
                    Write-Host "  [DIR]  $relativePath" -ForegroundColor Cyan
                } else {
                    $sizeKB = [math]::Round($_.Length / 1KB, 2)
                    Write-Host "  [FILE] $relativePath ($sizeKB KB)" -ForegroundColor Gray
                }
            }
    } catch {
        Write-Host "  无法列出剩余内容" -ForegroundColor Gray
    }
    
    $exitCode = 1
} else {
    Write-Host "  [成功] 目录已完全删除" -ForegroundColor Green
    $exitCode = 0
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
if ($exitCode -eq 0) {
    Write-Host "清理完成！" -ForegroundColor Green
} else {
    Write-Host "清理未完全成功" -ForegroundColor Red
}
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "按任意键退出..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')

exit $exitCode
