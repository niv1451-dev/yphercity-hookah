param([string]$yft)
$cw = 'D:\CodeWalker\CodeWalker30_dev46'
Add-Type -Path (Join-Path $cw 'CodeWalker.Core.dll')
$y = New-Object CodeWalker.GameFiles.YftFile
$y.Load([IO.File]::ReadAllBytes($yft))
$f = $y.Fragment
$tag = @{}; foreach ($b in $f.Drawable.Skeleton.Bones.Items) { $tag[[int]$b.Tag] = $b.Name }
"== $([IO.Path]::GetFileName($yft))"
$m = $f.Drawable.FragMatrix
"main FragMatrix type: $($m.GetType().FullName)"
($m | Format-List | Out-String).Trim()
$i = 0
foreach ($c in $f.PhysicsLODGroup.PhysicsLOD1.Children.data_items) {
    $d = $c.Drawable1
    if ($d -and $tag[[int]$c.BoneTag] -match 'wheel') { "child $i $($tag[[int]$c.BoneTag]):"; ($d.FragMatrix | Format-List | Out-String).Trim() }
    $i++
}
