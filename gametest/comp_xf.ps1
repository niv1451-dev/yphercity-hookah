param([string]$yft)
$cw = 'D:\CodeWalker\CodeWalker30_dev46'
Add-Type -Path (Join-Path $cw 'CodeWalker.Core.dll')
$y = New-Object CodeWalker.GameFiles.YftFile
$y.Load([IO.File]::ReadAllBytes($yft))
$f = $y.Fragment
$tag = @{}; foreach ($b in $f.Drawable.Skeleton.Bones.Items) { $tag[[int]$b.Tag] = $b.Name }
$lod = $f.PhysicsLODGroup.PhysicsLOD1
$comp = $lod.Bound
"== $([IO.Path]::GetFileName($yft))"
for ($i = 0; $i -lt $comp.Children.data_items.Length; $i++) {
    $m = $comp.ChildrenTransformation1[$i]
    $m2 = $comp.ChildrenTransformation2[$i]
    $b = $comp.Children.data_items[$i]
    $c = $b.BoxCenter
    '  [{0}] {1,-14} T1=({2:N3},{3:N3},{4:N3}) T2=({5:N3},{6:N3},{7:N3}) col2=({8:N2},{9:N2},{10:N2}) boxCenter=({11:N3},{12:N3},{13:N3})' -f $i, $tag[[int]$lod.Children.data_items[$i].BoneTag], $m.Column4.X, $m.Column4.Y, $m.Column4.Z, $m2.Column4.X, $m2.Column4.Y, $m2.Column4.Z, $m.Column2.X, $m.Column2.Y, $m.Column2.Z, $c.X, $c.Y, $c.Z
}
