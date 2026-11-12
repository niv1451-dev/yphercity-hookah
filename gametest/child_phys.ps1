param([string]$yft)
$cw = 'D:\CodeWalker\CodeWalker30_dev46'
Add-Type -Path (Join-Path $cw 'CodeWalker.Core.dll')
$y = New-Object CodeWalker.GameFiles.YftFile
$y.Load([IO.File]::ReadAllBytes($yft))
$f = $y.Fragment
$tag = @{}; foreach ($b in $f.Drawable.Skeleton.Bones.Items) { $tag[[int]$b.Tag] = $b.Name }
$lod = $f.PhysicsLODGroup.PhysicsLOD1
"== $([IO.Path]::GetFileName($yft))"
"UnkVecs count=$($lod.ChildrenUnkVecs.Length) Inertia count=$($lod.ChildrenInertiaTensors.Length) UnkFloats=$($lod.ChildrenUnkFloats -join ',')"
for ($i = 0; $i -lt $lod.Children.data_items.Length; $i++) {
  $v = $lod.ChildrenUnkVecs[$i]; $it = $lod.ChildrenInertiaTensors[$i]; $c = $lod.Children.data_items[$i]
  '[{0}] {1,-13} unkVec=({2:N3},{3:N3},{4:N3},{5:N3}) inertia=({6:N4},{7:N4},{8:N4},{9:N4}) mass1={10:N2} mass2={11:N2} grp={12}' -f $i,$tag[[int]$c.BoneTag],$v.X,$v.Y,$v.Z,$v.W,$it.X,$it.Y,$it.Z,$it.W,$c.PristineMass,$c.DamagedMass,$c.GroupIndex
}
"Unknown vectors on LOD: 50h=$($lod.Unknown_50h) 5Ch=$($lod.Unknown_5Ch) 6Ch=$($lod.Unknown_6Ch) 7Ch=$($lod.Unknown_7Ch) 8Ch=$($lod.Unknown_8Ch) 9Ch=$($lod.Unknown_9Ch) ACh=$($lod.Unknown_ACh) BCh=$($lod.Unknown_BCh)"
"Damping LC=$($lod.DampingLinearC) LV=$($lod.DampingLinearV) LV2=$($lod.DampingLinearV2) AC=$($lod.DampingAngularC) AV=$($lod.DampingAngularV) AV2=$($lod.DampingAngularV2)"
