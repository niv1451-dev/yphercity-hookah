param([string]$yft)
# Read-only: per physics child, the transforms the game uses to place it (composite child matrix, link attachment,
# child "matrix" fields) and the wheel bones' default transforms.
$cw = 'D:\CodeWalker\CodeWalker30_dev46'
Add-Type -Path (Join-Path $cw 'CodeWalker.Core.dll')
$y = New-Object CodeWalker.GameFiles.YftFile
$y.Load([IO.File]::ReadAllBytes($yft))
$f = $y.Fragment
$lod = $f.PhysicsLODGroup.PhysicsLOD1
"== $([IO.Path]::GetFileName($yft))"
"LOD props: " + (($lod | Get-Member -MemberType Property | ForEach-Object { $_.Name }) -join ', ')
function M($m) {
    if ($m -eq $null) { return 'null' }
    if ($m.M41 -ne $null) { return ('T=({0:N3},{1:N3},{2:N3}) X=({3:N2},{4:N2},{5:N2}) Y=({6:N2},{7:N2},{8:N2})' -f $m.M41, $m.M42, $m.M43, $m.M11, $m.M12, $m.M13, $m.M21, $m.M22, $m.M23) }
    if ($m.Row4 -ne $null) { return ('T=({0:N3},{1:N3},{2:N3}) R1=({3:N2},{4:N2},{5:N2})' -f $m.Row4.X, $m.Row4.Y, $m.Row4.Z, $m.Row1.X, $m.Row1.Y, $m.Row1.Z) }
    return ($m | Get-Member | ForEach-Object { $_.Name }) -join ','
}
$comp = $lod.Bound
"composite transforms:"
for ($i = 0; $i -lt $comp.Children.data_items.Length; $i++) { "  [$i] " + (M $comp.ChildrenTransformation1[$i]) }
if ($lod.FragTransforms) { "frag transforms (per child):"; $k = 0; foreach ($la in $lod.FragTransforms.Matrices) { "  [$k] " + (M $la); $k++ } }
"PositionOffset: $($lod.PositionOffset)  Unknown_50h: $($lod.Unknown_50h)"
"children matrices:"
$i = 0
foreach ($c in $lod.Children.data_items) {
    $props = ($c | Get-Member -MemberType Property | Where-Object { $_.Name -match 'Matrix|Unknown_[0-9A-F]+h$' } | ForEach-Object { $_.Name })
    $d = $c.Drawable1
    $fm = if ($d) { M $d.FrameMatrix } else { '-' }
    "  [$i] tag=$($c.BoneTag) drawable.FrameMatrix: $fm"
    $i++
}
"skeleton wheel bones:"
foreach ($b in $f.Drawable.Skeleton.Bones.Items) { if ($b.Name -match 'wheel_l|swingarm|forks') { "  $($b.Name) T=($([math]::Round($b.Translation.X,3)),$([math]::Round($b.Translation.Y,3)),$([math]::Round($b.Translation.Z,3))) R=($([math]::Round($b.Rotation.X,3)),$([math]::Round($b.Rotation.Y,3)),$([math]::Round($b.Rotation.Z,3)),$([math]::Round($b.Rotation.W,3)))" } }
