# Windows: turn the CodeWalker XML that export.py writes into the binary game files with CodeWalker.Core (no window).
# Usage: powershell -ExecutionPolicy Bypass -File cw_convert.ps1 <gta_dir> [<codewalker_dir>]
# Writes onebike.yft, onebike_hi.yft and onebike.ytd next to the XML (the ytd takes its DDS files from <gta_dir>\onebike).
# CodeWalker is the reference for these files: it keeps every physics value from the XML (Sollumz's own binary
# writer dropped part of the child inertia).
param([string]$Dir, [string]$CodeWalker = 'D:\CodeWalker\CodeWalker30_dev46')
$ErrorActionPreference = 'Stop'
Add-Type -Path (Join-Path $CodeWalker 'CodeWalker.Core.dll')
$texDir = [string](Join-Path $Dir 'onebike')
function Convert-One([string]$xmlName, [string]$typeName, [string]$method, [string]$outName) {
    $xmlPath = Join-Path $Dir $xmlName
    $text = [string][IO.File]::ReadAllText($xmlPath)
    $t = [CodeWalker.GameFiles.YtdFile].Assembly.GetTypes() | Where-Object { $_.Name -eq $typeName } | Select-Object -First 1
    $m = $t.GetMethods() | Where-Object { $_.Name -eq $method -and $_.GetParameters().Count -eq 2 -and $_.GetParameters()[0].ParameterType -eq [string] } | Select-Object -First 1
    $obj = $m.Invoke($null, [object[]]@($text, $texDir))
    $bytes = $obj.Save()
    [IO.File]::WriteAllBytes((Join-Path $Dir $outName), $bytes)
    "$outName  $($bytes.Length) bytes"
}
Convert-One 'onebike.yft.xml' 'XmlYft' 'GetYft' 'onebike.yft'
Convert-One 'onebike_hi.yft.xml' 'XmlYft' 'GetYft' 'onebike_hi.yft'
Convert-One 'onebike.ytd.xml' 'XmlYtd' 'GetYtd' 'onebike.ytd'
