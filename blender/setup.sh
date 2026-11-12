#!/usr/bin/env bash
# One-time setup for a fresh container: Blender as a Python module (bpy), and the
# Sollumz add-on with its szio dependency for GTA V (CodeWalker XML) export.
set -euo pipefail
cd "$(dirname "$0")"

SOLLUMZ_COMMIT=f12e76891a3b199ef9c380eab11ef578a736b5cf

command -v uv >/dev/null || pip install -q uv
[ -x .venv/bin/python ] || uv venv -q --python 3.13 .venv
uv pip install -q --python .venv/bin/python bpy==5.2.3 pillow numpy "szio==1.4.0.dev3"

if [ ! -d bscripts/addons/sollumz_dev/.git ]; then
  mkdir -p bscripts/addons/sollumz_dev
  git -C bscripts/addons/sollumz_dev init -q
  git -C bscripts/addons/sollumz_dev fetch -q --depth 1 https://github.com/Sollumz/Sollumz.git "$SOLLUMZ_COMMIT"
  git -C bscripts/addons/sollumz_dev checkout -q FETCH_HEAD
fi

.venv/bin/python -c "import bpy; print('bpy', bpy.app.version_string)"
