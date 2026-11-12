param([string]$yft)
$cw = 'D:\CodeWalker\CodeWalker30_dev46'
Add-Type -Path (Join-Path $cw 'CodeWalker.Core.dll')
$y = New-Object CodeWalker.GameFiles.YftFile
$y.Load([IO.File]::ReadAllBytes($yft))
$sk = $y.Fragment.Drawable.Skeleton
"== $([IO.Path]::GetFileName($yft)) bones=$($sk.Bones.Items.Length) transforms=$($sk.Transformations.Length) inv=$($sk.TransformationsInverted.Length) flags=$($sk.Unknown_1Ch) $($sk.Unknown_50h) $($sk.Unknown_54h) $($sk.Unknown_58h)"
for ($i=0; $i -lt $sk.Bones.Items.Length; $i++) {
  $b = $sk.Bones.Items[$i]
  if ($b.Name -notmatch 'chassis$|wheel_l|swingarm|forks|seat_f|handlebars') { continue }
  $m = $sk.Transformations[$i]; $n = $sk.TransformationsInverted[$i]
  '{0,-12} idx={1} parent={2} local=({3:N3},{4:N3},{5:N3}) Trans=({6:N3},{7:N3},{8:N3}) Inv=({9:N3},{10:N3},{11:N3}) flags={12}' -f $b.Name,$i,$b.ParentIndex,$b.Translation.X,$b.Translation.Y,$b.Translation.Z,$m.M41,$m.M42,$m.M43,$n.M41,$n.M42,$n.M43,$b.Flags
}
