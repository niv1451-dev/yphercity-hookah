param([string]$yft, [string]$boneName = 'wheel_lf')
$cw = 'D:\CodeWalker\CodeWalker30_dev46'
Add-Type -Path (Join-Path $cw 'CodeWalker.Core.dll')
$y = New-Object CodeWalker.GameFiles.YftFile
$y.Load([IO.File]::ReadAllBytes($yft))
$f = $y.Fragment
$tag = @{}; foreach ($b in $f.Drawable.Skeleton.Bones.Items) { $tag[[int]$b.Tag] = $b.Name }
"== $([IO.Path]::GetFileName($yft))"
foreach ($c in $f.PhysicsLODGroup.PhysicsLOD1.Children.data_items) {
  if ($tag[[int]$c.BoneTag] -ne $boneName -or -not $c.Drawable1 -or $c.Drawable1.AllModels.Length -eq 0) { continue }
  $d = $c.Drawable1
  "drawable bbox=$($d.BoundingBoxMin) .. $($d.BoundingBoxMax) center=$($d.BoundingCenter) R=$($d.BoundingSphereRadius) shaderGroup=$([bool]$d.ShaderGroup)"
  foreach ($m in $d.DrawableModels.High) { foreach ($g in $m.Geometries) {
    $sh = $g.Shader
    $nm = [CodeWalker.GameFiles.JenkIndex]::TryGetString($sh.Name.Hash)
    "  geom shader=$nm ($($sh.Name.Hash)) bbox=$($g.AABB.Min) .. $($g.AABB.Max)"
    $ps = $sh.ParametersList
    for ($i = 0; $i -lt $ps.Count; $i++) {
      $p = $ps.Parameters[$i]; $h = $ps.Hashes[$i]
      $pn = [CodeWalker.GameFiles.JenkIndex]::TryGetString([uint32]$h)
      $val = if ($p.Data -is [CodeWalker.GameFiles.TextureBase]) { 'tex:' + $p.Data.Name } elseif ($p.Data -is [array]) { ($p.Data | ForEach-Object { "$_" }) -join ';' } else { "$($p.Data)" }
      "     $pn ($h) = $val"
    }
  } ; break }
  break
}
