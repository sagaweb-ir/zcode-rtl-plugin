# On-demand ZCode restarter used by "/rtl-fix on" when the debug port is
# closed (Electron only reads --remote-debugging-port at process start, so
# opening the port requires one app restart).
#   powershell -File restart-zcode.ps1            -> restart WITH the port
#   powershell -File restart-zcode.ps1 -NoPort    -> restart without (full off)
# The exe is auto-detected; override with -ZCodeExe "C:\path\ZCode.exe".
param(
  [switch]$NoPort,
  [string]$ZCodeExe = ""
)
$ErrorActionPreference = "SilentlyContinue"
$port = 9222

if (-not $ZCodeExe) {
  $candidates = @(
    (Join-Path $env:LOCALAPPDATA "Programs\zcode\ZCode.exe"),
    (Join-Path $env:LOCALAPPDATA "Programs\ZCode\ZCode.exe"),
    "C:\Program Files\zcode\ZCode.exe",
    "C:\Program Files\ZCode\ZCode.exe",
    "D:\app\zcode\ZCode.exe",
    "J:\app\zcode\ZCode.exe"
  )
  $sh = New-Object -ComObject WScript.Shell
  $roots = @("$env:APPDATA\Microsoft\Windows\Start Menu\Programs",
             "$env:ProgramData\Microsoft\Windows\Start Menu\Programs")
  foreach ($root in $roots) {
    Get-ChildItem -Path $root -Recurse -Filter "*.lnk" -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -like "*zcode*" } |
      ForEach-Object { $candidates += $sh.CreateShortcut($_.FullName).TargetPath }
  }
  $ZCodeExe = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}
if (-not $ZCodeExe -or -not (Test-Path $ZCodeExe)) {
  Write-Host "ZCode.exe not found. Run with -ZCodeExe 'C:\path\to\ZCode.exe'"
  exit 1
}

# Graceful close first; force after a grace period (tray apps ignore WM_CLOSE).
taskkill /IM ZCode.exe | Out-Null
Start-Sleep -Seconds 3
if (Get-Process ZCode -ErrorAction SilentlyContinue) {
  taskkill /F /IM ZCode.exe | Out-Null
  Start-Sleep -Seconds 2
}

# v0.4.4-fork: make the flag survive MANUAL restarts too. Electron reads
# --remote-debugging-port only at process start, and users reopen the app
# from pinned/Start Menu shortcuts — if those don't carry the flag, every
# manual open/close silently loses the port and the RTL layer with it.
# Restarting WITH the port adds the flag to all ZCode shortcuts; -NoPort
# strips it back out (full off must also restore default shortcuts).
$flag = "--remote-debugging-port=$port"
function Set-ShortcutFlag([bool]$enable) {
  $sh = New-Object -ComObject WScript.Shell
  $dirs = @("$env:APPDATA\Microsoft\Windows\Start Menu\Programs",
            "$env:ProgramData\Microsoft\Windows\Start Menu\Programs",
            "$env:USERPROFILE\Desktop", "$env:PUBLIC\Desktop",
            "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar")
  $patched = 0
  foreach ($d in $dirs) {
    Get-ChildItem -Path $d -Recurse -Filter "*.lnk" -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -like "*zcode*" } |
      ForEach-Object {
        $s = $sh.CreateShortcut($_.FullName)
        if ($s.TargetPath -notlike "*ZCode.exe") { return }
        if ($enable -and $s.Arguments -notlike "*$flag*") {
          $s.Arguments = ($s.Arguments + " " + $flag).Trim(); $s.Save(); $patched++
        } elseif (-not $enable -and $s.Arguments -like "*$flag*") {
          $s.Arguments = ($s.Arguments -replace [regex]::Escape($flag), "").Trim(); $s.Save(); $patched++
        }
      }
  }
  Write-Host ("Shortcuts: " + $(if ($enable) { "now always open the debug port" } else { "restored to default (no port)" }) + " ($patched updated).")
}
Set-ShortcutFlag (-not $NoPort)

$arg = if ($NoPort) { "" } else { "--remote-debugging-port=$port" }
Start-Process -FilePath $ZCodeExe -ArgumentList $arg
Write-Host ("ZCode restarted " + $(if ($NoPort) { "WITHOUT" } else { "WITH" }) + " the debug port ($port).")
