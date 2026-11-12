"""Run a project script inside the installed Blender on Windows (there is no bpy module or .venv there).

Usage (from blender/):
  & $env:BLENDER -b --factory-startup --python-exit-code 1 --python win.py -- render.py <out_dir> 1000 32 photo
Pillow comes from blender/.pylib, installed by setup_win.ps1.
"""
import os
import runpy
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '.pylib'))
sys.path.insert(0, HERE)

args = sys.argv[sys.argv.index('--') + 1:]
script = args[0] if os.path.isabs(args[0]) else os.path.join(HERE, args[0])
sys.argv = [script] + args[1:]
runpy.run_path(script, run_name='__main__')
