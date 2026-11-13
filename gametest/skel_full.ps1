param([string]$yft)
# השוואת השלד: מפרקים, מגבלות סיבוב, אינדקסים של הורים וילדים
$cw = 'D:\CodeWalker\CodeWalker30_dev46'
Add-Type -Path (Join-Path $cw 'CodeWalker.Core.dll')
$y = New-Object CodeWalker.GameFiles.YftFile
$y.Load([IO.File]::ReadAllBytes($yft))
$d = $y.Fragment.Drawable
$sk = $d.Skeleton
"== $([IO.Path]::GetFileName($yft))"
foreach ($p in ($sk | Get-Member -MemberType Property)) { $v = $sk.($p.Name); if (($v -is [ValueType] -or $v -is [string]) -and $p.Name -notmatch 'Pointer$|FilePosition|BlockLength|VFT') { "  SK.$($p.Name) = $v" } }
"  ParentIndices = $(($sk.ParentIndices) -join ',')"
"  ChildIndices = $(($sk.ChildIndices) -join ',')"
$j = $d.Joints
if ($j) { foreach ($p in ($j | Get-Member -MemberType Property)) { $v = $j.($p.Name); if (($v -is [ValueType]) -and $p.Name -notmatch 'Pointer$|FilePosition|BlockLength|VFT') { "  J.$($p.Name) = $v" } }
  $tagname = @{}; foreach ($b in $sk.Bones.Items) { $tagname[[int]$b.Tag] = $b.Name }
  if ($j.RotationLimits) { foreach ($r in $j.RotationLimits) { "  rotlimit bone=$($tagname[[int]$r.BoneId]) min=$($r.Min) max=$($r.Max) unk=$($r.NumControlPoints) $($r.JointType)" } }
  if ($j.TranslationLimits) { foreach ($r in $j.TranslationLimits) { "  translimit bone=$($tagname[[int]$r.BoneId]) min=$($r.Min) max=$($r.Max)" } }
} else { '  אין טבלת מגבלות מפרקים' }
foreach ($b in $sk.Bones.Items) { if ($b.Name -match 'chassis$|wheel_l|swingarm|forks|handlebars|seat_f') { "  bone $($b.Name) idx=$($b.Index) parent=$($b.ParentIndex) next=$($b.NextSiblingIndex) tag=$($b.Tag) flags=$($b.Flags) scale=$($b.Scale) u1=$($b.Unknown_1Ch) u2=$($b.Unknown_34h) u3=$($b.Unknown_48h)" } }
