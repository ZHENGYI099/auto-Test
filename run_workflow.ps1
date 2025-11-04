<#
.SYNOPSIS
    Automates the test workflow: CSV to JSON, AI enrichment, optimized test case generation, and test execution.

.DESCRIPTION
    - Converts CSV to JSON using csv_to_json.py
    - Generates enriched test case with run_coordinator.py
    - Generates optimized test case with test_optimized_generation.py
    - Executes the test with manual verification support
    - Provides colored progress output, error handling, and logging

.PARAMETER CsvFilePath
    Path to the CSV test case file.

.PARAMETER TestCaseId
    Test case ID (e.g., "testcase-134714753").

.PARAMETER ApiRate
    (Optional) API call interval in seconds. Default: 0.5

.PARAMETER SkipExecution
    (Optional) Switch to skip the final test execution step.

.EXAMPLE
    .\run_workflow.ps1 -CsvFilePath "C:\path\to\test.csv" -TestCaseId "testcase-134714753"
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$CsvFilePath,

    [Parameter(Mandatory = $true)]
    [string]$TestCaseId,

    [Parameter(Mandatory = $false)]
    [double]$ApiRate = 0.5,

    [Parameter(Mandatory = $false)]
    [switch]$SkipExecution
)

#region Helper Functions

function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "$timestamp [$Level] $Message"
    Add-Content -Path $Global:LogFilePath -Value $entry
}

function Write-Colored {
    param (
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Throw-Error {
    param (
        [string]$Message
    )
    Write-Colored $Message "Red"
    Write-Log $Message "ERROR"
    throw $Message
}

function Check-FileExists {
    param (
        [string]$FilePath,
        [string]$Description
    )
    if (-not (Test-Path $FilePath)) {
        Throw-Error "$Description not found: $FilePath"
    }
}

function Run-PythonScript {
    param (
        [string]$ScriptPath,
        [string]$Arguments,
        [string]$StepName,
        [string]$SuccessMessage,
        [string]$OutputFile
    )
    Write-Colored "[$StepName] Running: python $ScriptPath $Arguments" "Cyan"
    Write-Log "[$StepName] Running: python $ScriptPath $Arguments"
    try {
        $process = Start-Process -FilePath "python" -ArgumentList "$ScriptPath $Arguments" -NoNewWindow -Wait -PassThru -ErrorAction Stop
        if ($process.ExitCode -ne 0) {
            Throw-Error "[$StepName] Python script failed with exit code $($process.ExitCode)."
        }
        if ($OutputFile) {
            Check-FileExists -FilePath $OutputFile -Description "[$StepName] Output file"
        }
        Write-Colored $SuccessMessage "Green"
        Write-Log $SuccessMessage "SUCCESS"
    }
    catch {
        Throw-Error "[$StepName] Exception: $($_.Exception.Message)"
    }
}

#endregion

#region Initialization

# Create outputs folder if not exists
$OutputsFolder = Join-Path -Path $PSScriptRoot -ChildPath "outputs"
if (-not (Test-Path $OutputsFolder)) {
    New-Item -Path $OutputsFolder -ItemType Directory | Out-Null
}

# Create timestamped log file
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$Global:LogFilePath = Join-Path $OutputsFolder "workflow_log_$timestamp.txt"
Write-Log "Workflow started for TestCaseId: $TestCaseId" "INFO"

#endregion

#region Input Validation

Write-Colored "Validating input parameters..." "Cyan"
Write-Log "Validating input parameters..."

if (-not (Test-Path $CsvFilePath)) {
    Throw-Error "CSV file not found: $CsvFilePath"
}

if ([string]::IsNullOrWhiteSpace($TestCaseId)) {
    Throw-Error "TestCaseId is required and cannot be empty."
}

if ($ApiRate -le 0) {
    Throw-Error "ApiRate must be a positive number."
}

Write-Colored "Input validation successful." "Green"
Write-Log "Input validation successful." "SUCCESS"

#endregion

#region Step 1: Convert CSV to JSON

$CsvToJsonScript = Join-Path $PSScriptRoot "csv_to_json.py"
Check-FileExists -FilePath $CsvToJsonScript -Description "CSV to JSON Python script"

$JsonOutputFile = Join-Path $OutputsFolder "$TestCaseId.json"
$CsvToJsonArgs = "`"$CsvFilePath`" `"$JsonOutputFile`""

Run-PythonScript -ScriptPath $CsvToJsonScript `
    -Arguments $CsvToJsonArgs `
    -StepName "CSV to JSON" `
    -SuccessMessage "CSV successfully converted to JSON: $JsonOutputFile" `
    -OutputFile $JsonOutputFile

#endregion

#region Step 2: Generate Enriched Test Case with AI

$CoordinatorScript = Join-Path $PSScriptRoot "run_coordinator.py"
Check-FileExists -FilePath $CoordinatorScript -Description "AI Coordinator Python script"

$EnrichedOutputFile = Join-Path $OutputsFolder "$TestCaseId.enriched.json"
$CoordinatorArgs = "`"$JsonOutputFile`" `"$EnrichedOutputFile`" --api-rate $ApiRate"

Run-PythonScript -ScriptPath $CoordinatorScript `
    -Arguments $CoordinatorArgs `
    -StepName "AI Enrichment" `
    -SuccessMessage "Enriched test case generated: $EnrichedOutputFile" `
    -OutputFile $EnrichedOutputFile

#endregion

#region Step 3: Generate Optimized Test Case

$OptimizedScript = Join-Path $PSScriptRoot "test_optimized_generation.py"
Check-FileExists -FilePath $OptimizedScript -Description "Optimized Test Case Python script"

$OptimizedOutputFile = Join-Path $OutputsFolder "$TestCaseId.optimized.json"
$OptimizedArgs = "`"$EnrichedOutputFile`" `"$OptimizedOutputFile`""

Run-PythonScript -ScriptPath $OptimizedScript `
    -Arguments $OptimizedArgs `
    -StepName "Optimized Test Case Generation" `
    -SuccessMessage "Optimized test case generated: $OptimizedOutputFile" `
    -OutputFile $OptimizedOutputFile

#endregion

#region Step 4: Execute the Test (Manual Verification Support)

if ($SkipExecution) {
    Write-Colored "Test execution step skipped as per parameter." "Yellow"
    Write-Log "Test execution step skipped as per parameter." "INFO"
}
else {
    Write-Colored "Preparing to execute the test case in an elevated PowerShell window..." "Cyan"
    Write-Log "Preparing to execute the test case in an elevated PowerShell window..."

    $ExecutionScript = Join-Path $PSScriptRoot "execute_test.ps1"
    Check-FileExists -FilePath $ExecutionScript -Description "Test Execution PowerShell script"

    $ExecutionArgs = "-TestCaseFile `"$OptimizedOutputFile`" -TestCaseId `"$TestCaseId`""
    $psCommand = "& `"$ExecutionScript`" $ExecutionArgs"

    try {
        Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `$psCommand"
        Write-Colored "Test execution launched in admin PowerShell window. Please follow manual verification steps." "Green"
        Write-Log "Test execution launched in admin PowerShell window." "SUCCESS"
    }
    catch {
        Throw-Error "Failed to launch test execution in admin PowerShell window: $($_.Exception.Message)"
    }
}

#endregion

Write-Colored "Workflow completed successfully for TestCaseId: $TestCaseId" "Green"
Write-Log "Workflow completed successfully for TestCaseId: $TestCaseId" "SUCCESS"
Write-Colored "Log file: $Global:LogFilePath" "Yellow"