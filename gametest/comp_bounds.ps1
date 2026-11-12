param([string]$yft)
$cw = 'D:\CodeWalker\CodeWalker30_dev46'
Add-Type -Path (Join-Path $cw 'CodeWalker.Core.dll')
$y = New-Object CodeWalker.GameFiles.YftFile
$y.Load([IO.File]::ReadAllBytes($yft))
$f = $y.Fragment
$lod = $f.PhysicsLODGroup.PhysicsLOD1
$comp = $lod.Bound
"== $([IO.Path]::GetFileName($yft))  comp: bbmin=$($comp.BoxMin) bbmax=$($comp.BoxMax) sphC=$($comp.SphereCenter) R=$([math]::Round($comp.SphereRadius,3))"
for ($i = 0; $i -lt $comp.Children.data_items.Length; $i++) {
    $b = $comp.Children.data_items[$i]
    $fl = $comp.ChildrenFlags1[$i]; $fl2 = $comp.ChildrenFlags2[$i]
    '  [{0}] {1,-10} min=({2:N3},{3:N3},{4:N3}) max=({5:N3},{6:N3},{7:N3}) sph=({8:N3},{9:N3},{10:N3}) R={11:N3} margin={12:N3} f1={13} f2={14}' -f $i, $b.Type, $b.BoxMin.X, $b.BoxMin.Y, $b.BoxMin.Z, $b.BoxMax.X, $b.BoxMax.Y, $b.BoxMax.Z, $b.SphereCenter.X, $b.SphereCenter.Y, $b.SphereCenter.Z, $b.SphereRadius, $b.Margin, $fl.Flags1, $fl.Flags2
}
