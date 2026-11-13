param([string]$yft, [string]$boneName = 'wheel_lr')
# השוואה: כל הערכים של ציור הגלגל (Drawable1) בתוך חלק הפיזיקה של הגלגל
$cw = 'D:\CodeWalker\CodeWalker30_dev46'
Add-Type -Path (Join-Path $cw 'CodeWalker.Core.dll')
$y = New-Object CodeWalker.GameFiles.YftFile
$y.Load([IO.File]::ReadAllBytes($yft))
$f = $y.Fragment
$tag = @{}; foreach ($b in $f.Drawable.Skeleton.Bones.Items) { $tag[[int]$b.Tag] = $b.Name }
$ci = 0
foreach ($c in $f.PhysicsLODGroup.PhysicsLOD1.Children.data_items) {
  $n = $tag[[int]$c.BoneTag]
  if ($n -eq $boneName) {
    foreach ($which in 'Drawable1','Drawable2') {
      $d = $c.$which
      if (-not $d) { "[$ci] $which = null"; continue }
      foreach ($p in ($d | Get-Member -MemberType Property)) { $v = $d.($p.Name); if ($v -is [ValueType] -or $v -is [string]) { "[$ci] $which.$($p.Name) = $v" } elseif ($v -eq $null) { "[$ci] $which.$($p.Name) = null" } else { "[$ci] $which.$($p.Name) = <$($v.GetType().Name)>" } }
      foreach ($lv in 'High','Med','Low','VLow') { $ms = $d.DrawableModels.$lv; "[$ci] $which models.$lv = $(if ($ms) { $ms.Length } else { 0 })" }
    }
  }
  $ci++
}
