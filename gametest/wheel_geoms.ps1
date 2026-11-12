param([string]$yft)
$cw = 'D:\CodeWalker\CodeWalker30_dev46'
Add-Type -Path (Join-Path $cw 'CodeWalker.Core.dll')
$y = New-Object CodeWalker.GameFiles.YftFile
$y.Load([IO.File]::ReadAllBytes($yft))
$f = $y.Fragment
$tag = @{}; foreach ($b in $f.Drawable.Skeleton.Bones.Items) { $tag[[int]$b.Tag] = $b.Name }
"== $([IO.Path]::GetFileName($yft))"
$i = 0
foreach ($c in $f.PhysicsLODGroup.PhysicsLOD1.Children.data_items) {
    $d = $c.Drawable1
    if ($d -and $d.AllModels -and $d.AllModels.Length -gt 0 -and $tag[[int]$c.BoneTag] -match 'wheel') {
        "child $i $($tag[[int]$c.BoneTag])"
        foreach ($m in $d.DrawableModels.High) {
            "  model boneIdx=$($m.BoneIndex) skin=$($m.HasSkin) bind=$($m.SkeletonBinding) matrices=$($m.BoneIdsCount)"
            foreach ($g in $m.Geometries) {
                $vd = $g.VertexData; $info = $vd.Info
                $sh = $g.Shader
                "    geom shader=$($sh.Name) file=$($sh.FileName) verts=$($vd.VertexCount) stride=$($vd.VertexStride) type=$($vd.VertexType) flags=$($info.Flags) types=$($info.Types) boneIds=$(if ($g.BoneIds) { $g.BoneIds -join ',' } else { '-' })"
            }
        }
        break
    }
    $i++
}
