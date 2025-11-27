# ============================================================
# Microsoft Cloud Managed Desktop Extension - WMI Commands
# ============================================================

# WMI Namespace
$namespace = "root\cmd\clientagent"

Write-Host "=== WMI Namespace: $namespace ===" -ForegroundColor Cyan
Write-Host ""

# 1. 列出所有可用的 WMI 类
Write-Host "Available WMI Classes:" -ForegroundColor Yellow
Get-WmiObject -Namespace $namespace -List | Where-Object { $_.Name -notlike "__*" -and $_.Name -notlike "CIM_*" -and $_.Name -notlike "MSFT_*" } | Select-Object Name | Format-Table -AutoSize

# 2. 检查 IoTHubMessage 类
Write-Host "`n=== IoTHubMessage Class ===" -ForegroundColor Cyan
$iotClass = Get-WmiObject -Namespace $namespace -Class "IoTHubMessage" -List
Write-Host "Properties:" -ForegroundColor Yellow
$iotClass.Properties | Select-Object Name, Type | Format-Table -AutoSize

Write-Host "Current Instances:" -ForegroundColor Yellow
$instances = Get-WmiObject -Namespace $namespace -Class "IoTHubMessage"
if ($instances) {
    $instances | Format-List *
} else {
    Write-Host "  No instances found" -ForegroundColor Gray
}

# 3. 检查 PluginStorage 类
Write-Host "`n=== PluginStorage Class ===" -ForegroundColor Cyan
$pluginClass = Get-WmiObject -Namespace $namespace -Class "PluginStorage" -List
Write-Host "Properties:" -ForegroundColor Yellow
$pluginClass.Properties | Select-Object Name, Type | Format-Table -AutoSize

# 4. 检查 PluginPolicy 类
Write-Host "`n=== PluginPolicy Class ===" -ForegroundColor Cyan
$policyClass = Get-WmiObject -Namespace $namespace -Class "PluginPolicy" -List
Write-Host "Properties:" -ForegroundColor Yellow
$policyClass.Properties | Select-Object Name, Type | Format-Table -AutoSize

# 5. 常用 WMI 查询命令
Write-Host "`n=== Common WMI Query Commands ===" -ForegroundColor Cyan
Write-Host @"

# 查询所有 IoTHubMessage
Get-WmiObject -Namespace "root\cmd\clientagent" -Class "IoTHubMessage"

# 查询所有 PluginStorage
Get-WmiObject -Namespace "root\cmd\clientagent" -Class "PluginStorage"

# 查询所有 PluginPolicy
Get-WmiObject -Namespace "root\cmd\clientagent" -Class "PluginPolicy"

# 查询所有 SchedulerEntity
Get-WmiObject -Namespace "root\cmd\clientagent" -Class "SchedulerEntity"

# 查询 HighPriorityIoTHubMessage
Get-WmiObject -Namespace "root\cmd\clientagent" -Class "HighPriorityIoTHubMessage"

# 查询特定属性
Get-WmiObject -Namespace "root\cmd\clientagent" -Class "IoTHubMessage" | Select-Object MessageId, Payload, CreatedAt

# 使用 WQL 查询
Get-WmiObject -Namespace "root\cmd\clientagent" -Query "SELECT * FROM IoTHubMessage WHERE MessageId IS NOT NULL"

"@ -ForegroundColor Gray
