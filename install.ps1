# Install Emba on Windows, for the current user. Nothing needs admin.
#
#   irm https://raw.githubusercontent.com/teslaoruz/emba/main/install.ps1 | iex
#
# Puts Emba in %LOCALAPPDATA%\Emba, adds an `emba` command and a Start menu
# entry, then asks before connecting any coding agent.
$ErrorActionPreference = "Stop"
$Repo = "https://github.com/teslaoruz/emba"
$App = Join-Path $env:LOCALAPPDATA "Emba"

function Say($text) { Write-Host "● $text" -ForegroundColor DarkYellow }

if ($args -contains "--uninstall") {
    if (Test-Path "$App\emba.cmd") {
        & "$App\emba.cmd" disconnect all
        & "$App\emba.cmd" autostart off
        & "$App\emba.cmd" quit
    }
    Remove-Item -Recurse -Force $App -ErrorAction SilentlyContinue
    Remove-Item -Force "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Emba.lnk" -ErrorAction SilentlyContinue
    Say "Emba is gone. Your settings in $env:APPDATA\emba are still there if you come back."
    return
}

# ---- Python 3.9+ ----
$py = Get-Command python -ErrorAction SilentlyContinue
if (-not $py -or -not (& python -c "import sys; print(sys.version_info >= (3, 9))" 2>$null) -eq "True") {
    Say "Emba needs Python. Installing it with winget..."
    winget install --id Python.Python.3.12 --silent --accept-package-agreements --accept-source-agreements
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "User") + ";" + [Environment]::GetEnvironmentVariable("Path", "Machine")
}

# ---- the app ----
Say "Downloading Emba"
$zip = Join-Path $env:TEMP "emba.zip"
Invoke-WebRequest "$Repo/archive/refs/heads/main.zip" -OutFile $zip
$unpacked = Join-Path $env:TEMP "emba-main"
Remove-Item -Recurse -Force $unpacked -ErrorAction SilentlyContinue
Expand-Archive $zip -DestinationPath $env:TEMP -Force
New-Item -ItemType Directory -Force $App | Out-Null
Copy-Item -Recurse -Force "$unpacked\*" $App
Remove-Item -Recurse -Force $unpacked, $zip

Say "Setting up Qt (one time, about 200 MB)"
if (-not (Test-Path "$App\.venv")) { python -m venv "$App\.venv" }
& "$App\.venv\Scripts\python.exe" -m pip install --quiet --upgrade pip PySide6

# ---- command, PATH, Start menu ----
Set-Content "$App\emba.cmd" "@`"%~dp0.venv\Scripts\python.exe`" `"%~dp0bin\emba`" %*" -Encoding ASCII
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$App*") {
    [Environment]::SetEnvironmentVariable("Path", "$userPath;$App", "User")
    $env:Path += ";$App"
}
$shell = New-Object -ComObject WScript.Shell
$link = $shell.CreateShortcut("$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Emba.lnk")
$link.TargetPath = "$App\.venv\Scripts\pythonw.exe"
$link.Arguments = "`"$App\bin\emba`" start"
$link.IconLocation = "$App\assets\emba.ico"
$link.Description = "A red panda that keeps an eye on your coding agents"
$link.Save()

# ---- connect, start ----
Say "Connecting to your coding agents (you'll see each change first)"
& "$App\emba.cmd" connect
$answer = Read-Host "Start Emba when you log in? [Y/n]"
if ($answer -notmatch "^[nN]") { & "$App\emba.cmd" autostart on }
& "$App\emba.cmd" start
Say "Done. Emba is in the corner of your screen. Try: emba settings"
