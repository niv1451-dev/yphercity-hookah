param([string]$yft, [string]$boneName = 'wheel_lf')
# טווחי הנתונים בכל נקודה של חלקי הגלגל: מערכת צבע ושתי מערכות מיפוי (UV0, UV1) והמשיק
$cw = 'D:\CodeWalker\CodeWalker30_dev46'
Add-Type -Path (Join-Path $cw 'CodeWalker.Core.dll')
$y = New-Object CodeWalker.GameFiles.YftFile
$y.Load([IO.File]::ReadAllBytes($yft))
$f = $y.Fragment
$tag = @{}; foreach ($b in $f.Drawable.Skeleton.Bones.Items) { $tag[[int]$b.Tag] = $b.Name }
"== $([IO.Path]::GetFileName($yft))"
foreach ($c in $f.PhysicsLODGroup.PhysicsLOD1.Children.data_items) {
  if ($tag[[int]$c.BoneTag] -ne $boneName -or -not $c.Drawable1 -or $c.Drawable1.AllModels.Length -eq 0) { continue }
  foreach ($m in $c.Drawable1.DrawableModels.High) { $gi = 0; foreach ($g in $m.Geometries) {
    $vd = $g.VertexData; $buf = $vd.VertexBytes; $st = $vd.VertexStride
    $mn = @(1e9,1e9,1e9,1e9,1e9,1e9,1e9,1e9); $mx = @(-1e9,-1e9,-1e9,-1e9,-1e9,-1e9,-1e9,-1e9)
    for ($v = 0; $v -lt $vd.VertexCount; $v += 3) {
      $o = $v * $st
      $vals = @([BitConverter]::ToSingle($buf, $o+28), [BitConverter]::ToSingle($buf, $o+32), [BitConverter]::ToSingle($buf, $o+36), [BitConverter]::ToSingle($buf, $o+40), [BitConverter]::ToSingle($buf, $o+44), [BitConverter]::ToSingle($buf, $o+48), [BitConverter]::ToSingle($buf, $o+52), [BitConverter]::ToSingle($buf, $o+56))
      for ($k = 0; $k -lt 8; $k++) { if ($vals[$k] -lt $mn[$k]) { $mn[$k] = $vals[$k] }; if ($vals[$k] -gt $mx[$k]) { $mx[$k] = $vals[$k] } }
    }
    '  חלק {0}: UV0 u[{1:N2},{2:N2}] v[{3:N2},{4:N2}]  UV1 u[{5:N3},{6:N3}] v[{7:N3},{8:N3}]  משיק w[{9:N2},{10:N2}]' -f $gi, $mn[0], $mx[0], $mn[1], $mx[1], $mn[2], $mx[2], $mn[3], $mx[3], $mn[7], $mx[7]
    $gi++ } }
  break
}
