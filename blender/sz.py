"""Enable the Sollumz add-on inside the bpy module."""
import os

import addon_utils
import bpy

SCRIPTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'bscripts')


def enable():
    prefs = bpy.context.preferences
    if not any(d.directory == SCRIPTS for d in prefs.filepaths.script_directories):
        d = prefs.filepaths.script_directories.new()
        d.directory = SCRIPTS
    bpy.utils.refresh_script_paths()
    addon_utils.modules_refresh()
    mod = addon_utils.enable('sollumz_dev', default_set=True, handle_error=None)
    if mod is None:
        raise RuntimeError('Sollumz failed to enable')
    return mod
