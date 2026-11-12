# Windows setup: use the installed Blender instead of the bpy module, Pillow goes to blender\.pylib.
# Sollumz (for export.py / verify.py) is the Blender extension installed from repo.sollumz.org.
$ErrorActionPreference = 'Stop'
$blender = if ($env:BLENDER) { $env:BLENDER } else { 'D:\Blender Foundation\Blender 5.2\blender.exe' }
$py = Get-ChildItem (Split-Path $blender) -Recurse -Depth 3 -Filter python.exe | Where-Object { $_.DirectoryName -like '*\python\bin' } | Select-Object -First 1 -ExpandProperty FullName
if (-not (Test-Path "$PSScriptRoot\.pylib\PIL")) {
    & $py -m pip install --disable-pip-version-check --no-input --only-binary ':all:' --target "$PSScriptRoot\.pylib" pillow
}
& $blender -b --factory-startup --python-expr "import bpy; print('bpy', bpy.app.version_string)"
