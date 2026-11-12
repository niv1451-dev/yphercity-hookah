param([string]$yft)
# Read-only: how a wheel child's drawable is built (models, bone index, skin flag, skeleton, matrices, vertex extent)
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
    if ($d -and $d.AllModels -and $d.AllModels.Length -gt 0) {
        "child $i bone=$($tag[[int]$c.BoneTag]) skeleton=$([bool]$d.Skeleton) jointsPtr=$($d.JointsPointer) frameMatrix? $(if ($d.PSObject.Properties['FrameMatrix']) { $d.FrameMatrix } else { 'n/a' })"
        $props = $d | Get-Member -MemberType Property | Where-Object { $_.Name -match 'Matrix|Unknown|Bound|Lod|Flags' } | ForEach-Object { $_.Name }
        "  drawable props: $($props -join ', ')"
        foreach ($m in $d.DrawableModels.High) {
            $minx = 1e9; $maxx = -1e9; $miny = 1e9; $maxy = -1e9; $minz = 1e9; $maxz = -1e9
            foreach ($g in $m.Geometries) {
                $vd = $g.VertexData
                if (-not $vd) { continue }
                $buf = $vd.VertexBytes; $stride = $vd.VertexStride
                for ($v = 0; $v -lt $vd.VertexCount; $v += 7) {
                    $x = [BitConverter]::ToSingle($buf, $v * $stride); $yv = [BitConverter]::ToSingle($buf, $v * $stride + 4); $z = [BitConverter]::ToSingle($buf, $v * $stride + 8)
                    if ($x -lt $minx) { $minx = $x }; if ($x -gt $maxx) { $maxx = $x }; if ($yv -lt $miny) { $miny = $yv }; if ($yv -gt $maxy) { $maxy = $yv }; if ($z -lt $minz) { $minz = $z }; if ($z -gt $maxz) { $maxz = $z }
                }
            }
            "  model boneIndex=$($m.BoneIndex) hasSkin=$($m.HasSkin) skeletonBinding=$($m.SkeletonBinding) flags=$($m.Flags) geoms=$($m.Geometries.Length) verts x[$([math]::Round($minx,3)),$([math]::Round($maxx,3))] y[$([math]::Round($miny,3)),$([math]::Round($maxy,3))] z[$([math]::Round($minz,3)),$([math]::Round($maxz,3))]"
        }
    }
    $i++
}
