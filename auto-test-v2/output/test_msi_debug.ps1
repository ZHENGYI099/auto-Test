# Debug script to check MSI Property trimming
$msiPath = "C:\VMShare\cmdextension.msi"

function Get-MSIProperty {
    param(
        [string]$msiPath,
        [string]$property
    )
    try {
        $installer = New-Object -ComObject WindowsInstaller.Installer
        $database = $installer.GetType().InvokeMember("OpenDatabase", 'InvokeMethod', $null, $installer, @($msiPath, 0))
        $query = "SELECT Value FROM Property WHERE Property = '$property'"
        $view = $database.GetType().InvokeMember("OpenView", 'InvokeMethod', $null, $database, ($query))
        $null = $view.GetType().InvokeMember("Execute", 'InvokeMethod', $null, $view, $null)  # Suppress output!
        $record = $view.GetType().InvokeMember("Fetch", 'InvokeMethod', $null, $view, $null)
        
        $value = $null
        if ($record -ne $null) {
            $value = $record.GetType().InvokeMember("StringData", 'GetProperty', $null, $record, 1)
        }
        
        # Save trimmed value BEFORE releasing COM objects
        if ([string]::IsNullOrWhiteSpace($value)) {
            $null = [System.Runtime.InteropServices.Marshal]::ReleaseComObject($view)
            $null = [System.Runtime.InteropServices.Marshal]::ReleaseComObject($database)
            $null = [System.Runtime.InteropServices.Marshal]::ReleaseComObject($installer)
            return $null
        }
        
        # Trim and convert to proper string
        $result = [string]$value.Trim()
        
        # Now release COM objects - assign to $null to suppress output
        $null = [System.Runtime.InteropServices.Marshal]::ReleaseComObject($view)
        $null = [System.Runtime.InteropServices.Marshal]::ReleaseComObject($database)
        $null = [System.Runtime.InteropServices.Marshal]::ReleaseComObject($installer)
        
        Write-Host "Result before return: [$result]" -ForegroundColor Cyan
        Write-Host "Result length: $($result.Length)" -ForegroundColor Cyan
        
        # Return the result
        return $result
    } catch {
        Write-Host "[DEBUG] Get-MSIProperty failed: $_" -ForegroundColor Red
        return $null
    }
}

Write-Host "Testing Get-MSIProperty function..." -ForegroundColor Cyan
$version = Get-MSIProperty -msiPath $msiPath -property "ProductVersion"
Write-Host ""
Write-Host "Returned value: [$version]" -ForegroundColor Magenta
Write-Host "Returned type: $($version.GetType().FullName)" -ForegroundColor Magenta
Write-Host "Returned length: $($version.Length)" -ForegroundColor Magenta

if ($version -is [Array]) {
    Write-Host "IT'S AN ARRAY!" -ForegroundColor Red
    for ($i = 0; $i -lt $version.Length; $i++) {
        Write-Host "  [$i]: [$($version[$i])] (length: $($version[$i].Length))" -ForegroundColor Yellow
    }
} else {
    Write-Host "It's a string" -ForegroundColor Green
}

# Test comparison
$testFile = "1.2.03179.270"
Write-Host ""
Write-Host "Test comparison:" -ForegroundColor Cyan
Write-Host "  File version: [$testFile]" -ForegroundColor White
Write-Host "  MSI version:  [$version]" -ForegroundColor White
Write-Host "  Are equal? $($testFile -eq $version)" -ForegroundColor $(if ($testFile -eq $version) { "Green" } else { "Red" })
