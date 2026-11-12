param([string]$yft)
$cw = 'D:\CodeWalker\CodeWalker30_dev46'
Add-Type -Path (Join-Path $cw 'CodeWalker.Core.dll')
$y = New-Object CodeWalker.GameFiles.YftFile
$y.Load([IO.File]::ReadAllBytes($yft))
$f = $y.Fragment
"== $([IO.Path]::GetFileName($yft))"
foreach ($p in ($f | Get-Member -MemberType Property)) { $v = $f.($p.Name); if ($v -is [ValueType] -or $v -is [string]) { "  F.$($p.Name) = $v" } }
$tag = @{}; $sk=$f.Drawable.Skeleton; foreach ($b in $sk.Bones.Items) { $tag[[int]$b.Tag] = $b.Name }
$lod = $f.PhysicsLODGroup.PhysicsLOD1
$gi = 0
foreach ($g in $lod.Groups.data_items) {
  $props = ($g | Get-Member -MemberType Property | Where-Object { $_.Name -notmatch 'FilePosition|BlockLength|Name$' } | ForEach-Object { $n=$_.Name; "$n=$($g.$n)" }) -join ' '
  "  G[$gi] $($lod.GroupNames.data_items[$gi].Name) $props"
  $gi++
}
$ci=0
foreach ($c in $lod.Children.data_items) {
  $props = ($c | Get-Member -MemberType Property | Where-Object { $_.Name -match 'Unknown|Flags|Mass|Group|Tag' } | ForEach-Object { $n=$_.Name; "$n=$($c.$n)" }) -join ' '
  "  C[$ci] $($tag[[int]$c.BoneTag]) $props"
  $ci++
}
