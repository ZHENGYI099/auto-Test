# ============================================================
# 检查并清理 CMD Extension WMI 命名空间
# ============================================================

# 检查管理员权限
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR - Must run as Administrator" -ForegroundColor Red
    pause
    exit 1
}

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "CMD Extension WMI Namespace Cleanup" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

$namespace = "root\cmd\clientagent"
$parentNamespace = "root\cmd"

# 检查子命名空间是否存在
Write-Host "[1/3] Checking WMI namespace: $namespace" -ForegroundColor Yellow
try {
    $null = Get-WmiObject -Namespace $namespace -List -ErrorAction Stop | Select-Object -First 1
    Write-Host "      ✅ Namespace EXISTS" -ForegroundColor Green
    $namespaceExists = $true
} catch {
    Write-Host "      ❌ Namespace NOT FOUND (already clean)" -ForegroundColor Gray
    $namespaceExists = $false
}

Write-Host ""

# 如果存在，显示内容
if ($namespaceExists) {
    Write-Host "[2/3] Namespace contents:" -ForegroundColor Yellow
    $classes = Get-WmiObject -Namespace $namespace -List | 
               Where-Object { $_.Name -notlike "__*" -and $_.Name -notlike "CIM_*" -and $_.Name -notlike "MSFT_*" } |
               Select-Object -ExpandProperty Name
    
    if ($classes) {
        Write-Host "      Found $($classes.Count) custom classes:" -ForegroundColor Gray
        foreach ($class in $classes) {
            Write-Host "        - $class" -ForegroundColor Gray
        }
    } else {
        Write-Host "      No custom classes found" -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "[3/3] Deleting namespace: $namespace" -ForegroundColor Yellow
    
    try {
        # 方法 1: 使用 WMI 删除命名空间
        $ns = Get-WmiObject -Namespace $parentNamespace -Class "__NAMESPACE" -Filter "Name='ClientAgent'"
        if ($ns) {
            $ns.Delete()
            Write-Host "      ✅ Namespace deleted successfully (Method 1)" -ForegroundColor Green
        } else {
            Write-Host "      ⚠️  Namespace object not found in parent" -ForegroundColor Yellow
            
            # 方法 2: 使用 MOF 删除
            Write-Host "      Trying alternative method..." -ForegroundColor Gray
            $mofContent = @"
#pragma namespace("\\\\.\\root\\cmd")
#pragma deleteinstance("ClientAgent", FAIL)
"@
            $mofFile = "$env:TEMP\delete_clientagent.mof"
            $mofContent | Out-File -FilePath $mofFile -Encoding ASCII
            
            $result = mofcomp.exe $mofFile 2>&1
            Remove-Item $mofFile -Force -ErrorAction SilentlyContinue
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "      ✅ Namespace deleted successfully (Method 2)" -ForegroundColor Green
            } else {
                Write-Host "      ❌ Failed to delete namespace" -ForegroundColor Red
                Write-Host "      Error: $result" -ForegroundColor Gray
            }
        }
    } catch {
        Write-Host "      ❌ Error deleting namespace: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    Write-Host ""
    
    # 验证删除
    Write-Host "Verifying deletion..." -ForegroundColor Yellow
    Start-Sleep -Seconds 1
    try {
        $null = Get-WmiObject -Namespace $namespace -List -ErrorAction Stop | Select-Object -First 1
        Write-Host "      ⚠️  Namespace still exists" -ForegroundColor Yellow
    } catch {
        Write-Host "      ✅ Namespace successfully removed" -ForegroundColor Green
    }
    
} else {
    Write-Host "[2/3] Namespace already clean - no action needed" -ForegroundColor Gray
    Write-Host "[3/3] Skipped deletion" -ForegroundColor Gray
}

Write-Host ""

# 检查父命名空间是否为空
Write-Host "Checking parent namespace: $parentNamespace" -ForegroundColor Yellow
try {
    $childNamespaces = Get-WmiObject -Namespace $parentNamespace -Class "__NAMESPACE"
    if ($childNamespaces) {
        Write-Host "      Parent namespace has $($childNamespaces.Count) child namespace(s):" -ForegroundColor Gray
        $childNamespaces | ForEach-Object { Write-Host "        - $($_.Name)" -ForegroundColor Gray }
    } else {
        Write-Host "      Parent namespace is empty" -ForegroundColor Gray
        Write-Host "      Consider deleting parent namespace 'root\cmd' if not used by other apps" -ForegroundColor Yellow
    }
} catch {
    Write-Host "      Parent namespace not found or inaccessible" -ForegroundColor Gray
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Cleanup Complete" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Summary:" -ForegroundColor Yellow
Write-Host "  - WMI namespaces are automatically cleaned during MSI uninstall" -ForegroundColor Gray
Write-Host "  - Manual cleanup is usually NOT needed" -ForegroundColor Gray
Write-Host "  - This script can be used to verify and force cleanup if needed" -ForegroundColor Gray
Write-Host ""

pause
