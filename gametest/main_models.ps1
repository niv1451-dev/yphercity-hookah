param([string]$yft)
$cw = 'D:\CodeWalker\CodeWalker30_dev46'
Add-Type -Path (Join-Path $cw 'CodeWalker.Core.dll')
$y = New-Object CodeWalker.GameFiles.YftFile
$y.Load([IO.File]::ReadAllBytes($yft))
$f = $y.Fragment
$sk = $f.Drawable.Skeleton
"== $([IO.Path]::GetFileName($yft))"
foreach ($lvl in 'High','Med','Low','VLow') {
  $ms = $f.Drawable.DrawableModels.$lvl
  if (-not $ms) { continue }
  foreach ($m in $ms) {
    $bn = if ($m.BoneIndex -lt $sk.Bones.Items.Length) { $sk.Bones.Items[$m.BoneIndex].Name } else { '?' }
    $minx = 1e9; $maxx = -1e9; $miny = 1e9; $maxy = -1e9; $minz = 1e9; $maxz = -1e9; $nv = 0
    foreach ($g in $m.Geometries) { $vd = $g.VertexData; if (-not $vd) { continue }; $buf = $vd.VertexBytes; $st = $vd.VertexStride; $nv += $vd.VertexCount
      for ($v = 0; $v -lt $vd.VertexCount; $v += 11) { $x = [BitConverter]::ToSingle($buf, $v*$st); $yy = [BitConverter]::ToSingle($buf, $v*$st+4); $z = [BitConverter]::ToSingle($buf, $v*$st+8)
        if ($x -lt $minx) {$minx=$x}; if ($x -gt $maxx) {$maxx=$x}; if ($yy -lt $miny) {$miny=$yy}; if ($yy -gt $maxy) {$maxy=$yy}; if ($z -lt $minz) {$minz=$z}; if ($z -gt $maxz) {$maxz=$z} } }
    '{0,-5} bone={1}({2}) skin={3} geoms={4} verts={5} x[{6:N2},{7:N2}] y[{8:N2},{9:N2}] z[{10:N2},{11:N2}]' -f $lvl, $bn, $m.BoneIndex, $m.HasSkin, $m.Geometries.Length, $nv, $minx, $maxx, $miny, $maxy, $minz, $maxz
  }
}
