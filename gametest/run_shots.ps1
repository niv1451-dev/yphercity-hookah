# In-game photo test: restart the home server (txAdmin brings it back), start FiveM connected to it, take a
# screenshot on every "EATTEST SHOT <name> <k>" line in the client log, stop at "EATTEST DONE".
# The game is left running so the user can ride.
param([string]$Out, [int]$TimeoutSec = 900)
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -Namespace Eat -Name Win -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(System.IntPtr h);
[DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr h, int cmd);
[DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, System.UIntPtr extra);
'@
New-Item -ItemType Directory -Force -Path $Out | Out-Null
Get-ChildItem -LiteralPath $Out -Filter *.png | Remove-Item -Force
function Read-Shared([string]$path) { $fs = [IO.File]::Open($path, 'Open', 'Read', 'ReadWrite'); try { (New-Object IO.StreamReader($fs)).ReadToEnd() } finally { $fs.Dispose() } }
function Front {
    $game = Get-Process | Where-Object { $_.ProcessName -like 'FiveM_*GTAProcess' -and $_.MainWindowHandle -ne 0 } | Select-Object -First 1
    if ($game) {
        [Eat.Win]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero); [Eat.Win]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
        [void][Eat.Win]::ShowWindow($game.MainWindowHandle, 9); [void][Eat.Win]::SetForegroundWindow($game.MainWindowHandle)
    }
}
function Shot([string]$path) {
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose()
}

$old = Get-CimInstance Win32_Process -Filter "Name='FXServer.exe'" | Where-Object { $_.CommandLine -match 'txAdminServerMode' }
"restarting server process(es): $(@($old).Count)"
if ($old) { $old | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -Confirm:$false } }
Start-Sleep -Seconds 5
$info = $null
for ($i = 0; $i -lt 80 -and -not $info; $i++) { Start-Sleep -Seconds 3; try { $info = Invoke-RestMethod -Uri 'http://127.0.0.1:30120/info.json' -TimeoutSec 5 } catch {} }
"server up: $([bool]$info)  onebike: $(@($info.resources) -contains 'cyphercity-onebike')"
Start-Sleep -Seconds 10

Get-Process | Where-Object { $_.ProcessName -like 'FiveM*' } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
$start = Get-Date
$logDir = Join-Path $env:LOCALAPPDATA 'FiveM\FiveM.app\logs'
[void](Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = 'explorer.exe fivem://connect/127.0.0.1:30120' })

$done = @{}; $result = 'TIMEOUT'
while ((Get-Date) -lt $start.AddSeconds($TimeoutSec)) {
    Start-Sleep -Milliseconds 250
    $log = Get-ChildItem -LiteralPath $logDir -Filter 'CitizenFX_log_*' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -gt $start } | Sort-Object LastWriteTime | Select-Object -Last 1
    if (-not $log) { continue }
    $text = Read-Shared $log.FullName
    if ($text -match 'Process crash captured') { $result = 'CRASH'; break }
    foreach ($m in [regex]::Matches($text, 'EATTEST (READY|DONE|SHOT (\S+) (\d+))')) {
        $key = $m.Groups[1].Value
        if ($done.ContainsKey($key)) { continue }
        $done[$key] = $true
        if ($key -eq 'READY') { Front; "ready after $([int]((Get-Date) - $start).TotalSeconds) s" }
        elseif ($key -eq 'DONE') { $result = 'DONE' }
        else { Front; Start-Sleep -Milliseconds 250; Shot (Join-Path $Out ("{0}_{1}.png" -f $m.Groups[2].Value, $m.Groups[3].Value)) }
    }
    if ($result -eq 'DONE') { break }
}
"RESULT: $result  shots: $((Get-ChildItem -LiteralPath $Out -Filter *.png).Count)  ($([int]((Get-Date) - $start).TotalSeconds) s)"
$log = Get-ChildItem -LiteralPath $logDir -Filter 'CitizenFX_log_*' | Sort-Object LastWriteTime | Select-Object -Last 1
(Read-Shared $log.FullName) -split "`n" | Select-String -Pattern 'EATTEST (INFO|FAIL)|SCRIPT ERROR|onebike.*(error|fail)' | Select-Object -Last 80 | ForEach-Object { $_.Line.Trim() }
