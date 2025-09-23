param(
  [string]$ImagePath = "popup_capture.png",
  [string]$ExpectText = "Setup completed successfully",
  [string]$WindowTitle = "Microsoft Cloud Managed Desktop Extension",
  [int]$WaitSeconds = 25,
  [int]$PollIntervalMs = 800
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

# Invoke Python vision verifier
$python = $env:PYTHON || 'python'
$cmd = "$python verify/vision_verify.py --image `"$ImagePath`" --expect `"$ExpectText`" --title `"$WindowTitle`""
Write-Host "Running: $cmd"
Invoke-Expression $cmd
if($LASTEXITCODE -eq 0){ Write-Host 'Verification success'; exit 0 } else { Write-Host 'Verification failed'; exit 1 }
