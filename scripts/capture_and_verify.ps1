# powershell -NoProfile -ExecutionPolicy Bypass -File scripts\capture_and_verify.ps1 `
# >>   -ImagePath screenshots\case34717304_step5.2.png `
# >>   -WindowTitle "Microsoft Cloud Managed Desktop Extension" `
# >>   -ExpectText "Title is {Microsoft Cloud Managed Desktop Extension}, and Message is {Microsoft Cloud Managed Desktop Extension Setup completed successfully.}" -CaseId 2025924.1 -Step 1

param(
  [string]$ImagePath = "popup_capture.png",
  [string]$ExpectText = "Setup completed successfully",
  [string]$WindowTitle = "Microsoft Cloud Managed Desktop Extension",
  [int]$WaitSeconds = 25,
  [int]$PollIntervalMs = 800,
  [string]$CaseId = '',
  [string]$Step = '',
  [string]$JsonOut = ''
)

# Locate window & capture helper (simplified). Falls back to full screen if window not found.
Add-Type @"
using System;using System.Runtime.InteropServices;using System.Text;public class WinUtil{[DllImport("user32.dll")]public static extern IntPtr FindWindow(string lpClass,string lpWindow);[DllImport("user32.dll")]public static extern bool GetWindowRect(IntPtr hWnd,out RECT r);public struct RECT{public int Left;public int Top;public int Right;public int Bottom;}}
"@

function Capture-WindowOrScreen {
  param([string]$Title,[string]$OutPath)
  Add-Type -AssemblyName System.Windows.Forms, System.Drawing
  $h = [WinUtil]::FindWindow($null,$Title)
  if($h -ne [IntPtr]::Zero){
    $r=[WinUtil+RECT]::new();[WinUtil]::GetWindowRect($h,[ref]$r)|Out-Null
    $w=$r.Right-$r.Left;$hgt=$r.Bottom-$r.Top
    if($w -le 0 -or $hgt -le 0){ throw "Invalid window rect" }
    $bmp=New-Object System.Drawing.Bitmap($w,$hgt);$g=[System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen([System.Drawing.Point]::new($r.Left,$r.Top),[System.Drawing.Point]::Empty,$bmp.Size)
  } else {
    $bounds=[System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp=New-Object System.Drawing.Bitmap($bounds.Width,$bounds.Height);$g=[System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($bounds.Location,[System.Drawing.Point]::Empty,$bounds.Size)
  }
  $bmp.Save($OutPath,[System.Drawing.Imaging.ImageFormat]::Png)
  Write-Host "Saved screenshot $OutPath"
}

$deadline = (Get-Date).AddSeconds($WaitSeconds)
$found=$false

# Ensure parent directory exists if user supplied a relative or nested path
$parentDir = Split-Path -Parent $ImagePath
if($parentDir -and -not (Test-Path $parentDir)) {
  New-Item -ItemType Directory -Force -Path $parentDir | Out-Null
}
while((Get-Date) -lt $deadline){
  try{
    Capture-WindowOrScreen -Title $WindowTitle -OutPath $ImagePath
    if(Test-Path $ImagePath){
      $found=$true;break
    }
  }catch{}
  Start-Sleep -Milliseconds $PollIntervalMs
}
if(-not $found){ Write-Warning "Window not captured (title may differ). Proceeding with last screen shot attempt." }

# If still no file, do one final full-screen capture attempt (empty title triggers fallback branch)
if(-not (Test-Path $ImagePath)) {
  try { Capture-WindowOrScreen -Title '' -OutPath $ImagePath } catch {}
}

# Invoke Python vision verifier (pass ExpectText verbatim; no title parameter)
# Abort if screenshot truly missing
if(-not (Test-Path $ImagePath)) {
  Write-Error "Screenshot file was not created: $ImagePath"; exit 1
}

# Invoke Python vision verifier (pass ExpectText verbatim; no title parameter)
if([string]::IsNullOrWhiteSpace($env:PYTHON)) { $python = 'python' } else { $python = $env:PYTHON }
# 直接在初始命令后面拼接可选参数；caseid/step 即使为空也允许传递空值
$cmd = "$python verify/vision_verify.py --image `"$ImagePath`" --expect `"$ExpectText`" --caseid `"$CaseId`" --step `"$Step`""
if(-not [string]::IsNullOrWhiteSpace($JsonOut)) { $cmd += " --json-out `"$JsonOut`"" }
Write-Host "Running: $cmd"
Invoke-Expression $cmd
if($LASTEXITCODE -eq 0){ Write-Host 'Verification success'; exit 0 } else { Write-Host 'Verification failed'; exit 1 }
