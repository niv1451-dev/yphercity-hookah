param([string]$yft, [string]$boneName = 'wheel_lf')
# אילו צבעי נקודות (סימוני כיפוף לחומר הצמיג) יש בכל חלק של הגלגל
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
    $cnt = @{}; $rmin = 1e9; $rmax = 0
    for ($v = 0; $v -lt $vd.VertexCount; $v++) {
      $o = $v * $st
      $col = '{0},{1},{2},{3}' -f $buf[$o+24], $buf[$o+25], $buf[$o+26], $buf[$o+27]
      if ($cnt.ContainsKey($col)) { $cnt[$col]++ } else { $cnt[$col] = 1 }
      $yy = [BitConverter]::ToSingle($buf, $o+4); $zz = [BitConverter]::ToSingle($buf, $o+8); $r = [math]::Sqrt($yy*$yy + $zz*$zz); if ($r -lt $rmin) { $rmin = $r }; if ($r -gt $rmax) { $rmax = $r }
    }
    $top = ($cnt.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 5 | ForEach-Object { "[$($_.Key)]x$($_.Value)" }) -join ' '
    '  חלק {0}: נקודות={1} רדיוס {2:N3}..{3:N3} צבעים: {4}' -f $gi, $vd.VertexCount, $rmin, $rmax, $top
    $gi++ } }
  break
}
