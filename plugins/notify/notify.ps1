# Windows balloon notification. Called with -File, so the title and text
# arrive as plain arguments and are never parsed as PowerShell.
param([string]$Title, [string]$Text, [string]$Kind = "Info")
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$n = New-Object System.Windows.Forms.NotifyIcon
$n.Icon = if ($Kind -eq "Warning") { [System.Drawing.SystemIcons]::Warning } else { [System.Drawing.SystemIcons]::Information }
$n.Visible = $true
$n.ShowBalloonTip(5000, $Title, $Text, $Kind)
Start-Sleep -Seconds 6
$n.Dispose()
