param([string]$yft)
# השוואת נתוני הפיזיקה הכלליים: מפרקים, ארכיטיפים, מרכז כובד
$cw = 'D:\CodeWalker\CodeWalker30_dev46'
Add-Type -Path (Join-Path $cw 'CodeWalker.Core.dll')
$y = New-Object CodeWalker.GameFiles.YftFile
$y.Load([IO.File]::ReadAllBytes($yft))
$lod = $y.Fragment.PhysicsLODGroup.PhysicsLOD1
"== $([IO.Path]::GetFileName($yft))"
foreach ($p in ($lod | Get-Member -MemberType Property)) { $v = $lod.($p.Name); if ($v -is [ValueType] -or $v -is [string]) { if ($p.Name -notmatch 'Pointer$|FilePosition|BlockLength') { "  LOD.$($p.Name) = $v" } } elseif ($v -eq $null) { "  LOD.$($p.Name) = null" } }
"  ArticulatedBodyType = $(if ($lod.ArticulatedBodyType) { 'קיים' } else { 'אין' })"
foreach ($an in 'Archetype1','Archetype2') { $a = $lod.$an; if (-not $a) { "  $an = null"; continue }; foreach ($p in ($a | Get-Member -MemberType Property)) { $v = $a.($p.Name); if (($v -is [ValueType] -or $v -is [string]) -and $p.Name -notmatch 'Pointer$|FilePosition|BlockLength|VFT') { "  $an.$($p.Name) = $v" } } }
$g = $y.Fragment.PhysicsLODGroup
foreach ($p in ($g | Get-Member -MemberType Property)) { $v = $g.($p.Name); if (($v -is [ValueType]) -and $p.Name -notmatch 'Pointer$|FilePosition|BlockLength') { "  GRP.$($p.Name) = $v" } }
