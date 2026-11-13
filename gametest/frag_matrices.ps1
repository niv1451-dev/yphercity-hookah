param([string]$yft)
# הדפסת טבלת המטריצות הפנימית (FragMatrices) של כל ציור בקובץ
$cw = 'D:\CodeWalker\CodeWalker30_dev46'
Add-Type -Path (Join-Path $cw 'CodeWalker.Core.dll')
$y = New-Object CodeWalker.GameFiles.YftFile
$y.Load([IO.File]::ReadAllBytes($yft))
$f = $y.Fragment
$tag = @{}; foreach ($b in $f.Drawable.Skeleton.Bones.Items) { $tag[[int]$b.Tag] = $b.Name }
function Show($label, $d) {
  if (-not $d) { return }
  "$label count=$($d.FragMatricesCount) cap=$($d.FragMatricesCapacity) indsCount=$($d.FragMatricesIndsCount) u3C=$($d.Unknown_3Ch) u4C=$($d.Unknown_4Ch)"
  if ($d.FragMatrices) { $k = 0; foreach ($m in ($d.FragMatrices | Select-Object -First ([int]$d.FragMatricesCount))) { '   M[{0}] C1=({1:N3},{2:N3},{3:N3}) C2=({4:N3},{5:N3},{6:N3}) C3=({7:N3},{8:N3},{9:N3}) C4=({10:N3},{11:N3},{12:N3})' -f $k,$m.Column1.X,$m.Column1.Y,$m.Column1.Z,$m.Column2.X,$m.Column2.Y,$m.Column2.Z,$m.Column3.X,$m.Column3.Y,$m.Column3.Z,$m.Column4.X,$m.Column4.Y,$m.Column4.Z; $k++ } }
  if ($d.FragMatricesInds) { '   inds(first 8): ' + (($d.FragMatricesInds | Select-Object -First 8) -join ',') }
}
"== $([IO.Path]::GetFileName($yft))"
Show 'main' $f.Drawable
$ci = 0
foreach ($c in $f.PhysicsLODGroup.PhysicsLOD1.Children.data_items) { Show "child[$ci] $($tag[[int]$c.BoneTag]) d1" $c.Drawable1; $ci++ }
