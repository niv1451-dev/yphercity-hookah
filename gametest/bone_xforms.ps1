param([string]$yft)
$cw = 'D:\CodeWalker\CodeWalker30_dev46'
Add-Type -Path (Join-Path $cw 'CodeWalker.Core.dll')
$y = New-Object CodeWalker.GameFiles.YftFile
$y.Load([IO.File]::ReadAllBytes($yft))
$f = $y.Fragment
$sk = $f.Drawable.Skeleton
"== $([IO.Path]::GetFileName($yft))"
$items = $f.BoneTransforms.Items
for ($i=0; $i -lt $items.Length; $i++) {
  $n = $sk.Bones.Items[$i].Name
  if ($n -notmatch 'chassis$|wheel_l|swingarm|forks|seat_f|handlebars') { continue }
  $m = $items[$i]
  '{0,-12} [{1}] R1=({2:N3},{3:N3},{4:N3} | {5:N3}) R2=({6:N3},{7:N3},{8:N3} | {9:N3}) R3=({10:N3},{11:N3},{12:N3} | {13:N3})' -f $n,$i,$m.Row1.X,$m.Row1.Y,$m.Row1.Z,$m.Row1.W,$m.Row2.X,$m.Row2.Y,$m.Row2.Z,$m.Row2.W,$m.Row3.X,$m.Row3.Y,$m.Row3.Z,$m.Row3.W
}
