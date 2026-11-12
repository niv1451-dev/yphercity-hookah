param([string]$yft)
$cw = 'D:\CodeWalker\CodeWalker30_dev46'
Add-Type -Path (Join-Path $cw 'CodeWalker.Core.dll')
$y = New-Object CodeWalker.GameFiles.YftFile
$y.Load([IO.File]::ReadAllBytes($yft))
$f = $y.Fragment
$tag = @{}; foreach ($b in $f.Drawable.Skeleton.Bones.Items) { $tag[[int]$b.Tag] = $b.Name }
"== $([IO.Path]::GetFileName($yft))  main skeleton bones=$($f.Drawable.Skeleton.Bones.Items.Length)"
$i = 0
foreach ($c in $f.PhysicsLODGroup.PhysicsLOD1.Children.data_items) {
    $d = $c.Drawable1
    if ($d -and $tag[[int]$c.BoneTag] -match 'wheel' -and $d.AllModels.Length -gt 0) {
        $sk = $d.Skeleton
        $same = [object]::ReferenceEquals($sk, $f.Drawable.Skeleton)
        "child $i $($tag[[int]$c.BoneTag]): skeleton bones=$($sk.Bones.Items.Length) sameObjectAsMain=$same"
        $b0 = $sk.Bones.Items[0]
        "   bone0 $($b0.Name) T=($([math]::Round($b0.Translation.X,3)),$([math]::Round($b0.Translation.Y,3)),$([math]::Round($b0.Translation.Z,3)))"
        $t0 = $sk.Transformations[0]; $ti0 = $sk.TransformationsInverted[0]
        '   T0=({0:N3},{1:N3},{2:N3}) Tinv0=({3:N3},{4:N3},{5:N3})' -f $t0.M41, $t0.M42, $t0.M43, $ti0.M41, $ti0.M42, $ti0.M43
    }
    $i++
}
