param([string]$Pattern, [string]$OutDir, [switch]$ListOnly)
# Read-only from the game: find files in GTA V's RPF archives by regex and copy them out (resources get their RSC7 header back).
$cw = 'D:\CodeWalker\CodeWalker30_dev46'
$gta = 'D:\SteamLibrary\steamapps\common\Grand Theft Auto V'
Add-Type -Path (Join-Path $cw 'CodeWalker.Core.dll')
New-Item -ItemType Directory -Force $OutDir | Out-Null
[CodeWalker.GameFiles.GTA5Keys]::LoadFromPath($gta, $null)
$rm = New-Object CodeWalker.GameFiles.RpfManager
$rm.Init($gta, [Action[string]] { param($m) }, [Action[string]] { param($m) }, $false, $true)
$hits = @()
foreach ($rpf in $rm.AllRpfs) {
    if ($rpf.AllEntries -eq $null) { continue }
    foreach ($e in $rpf.AllEntries) { if ($e.Path -match $Pattern) { $hits += $e } }
}
"found $($hits.Count)"
foreach ($e in $hits) {
    "  $($e.Path)"
    if ($ListOnly -or $e -is [CodeWalker.GameFiles.RpfDirectoryEntry]) { continue }
    $data = $e.File.ExtractFile($e)
    if ($e -is [CodeWalker.GameFiles.RpfResourceFileEntry]) {
        $data = [CodeWalker.GameFiles.ResourceBuilder]::AddResourceHeader($e, [CodeWalker.GameFiles.ResourceBuilder]::Compress($data))
    }
    if ($data -eq $null) { continue }
    $safe = ($e.Path -replace '[\\/:]', '__')
    [IO.File]::WriteAllBytes((Join-Path $OutDir $safe), $data)
}
