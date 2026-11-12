"""Enable the Sollumz add-on.

Linux container: the bpy module with Sollumz cloned into blender/bscripts/addons/sollumz_dev (setup.sh).
Windows PC: the Sollumz extension installed in Blender from repo.sollumz.org (bl_ext.sollumz_repo.sollumz);
run Blender WITHOUT --factory-startup so the user's preferences (and the extension) are loaded.
PKG is the package name to import Sollumz modules from.
"""
import os

import addon_utils
import bpy

SCRIPTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'bscripts')
EXTENSION = 'bl_ext.sollumz_repo.sollumz'
PKG = 'sollumz_dev'


def extension_enabled():
    return any(a.module == EXTENSION for a in bpy.context.preferences.addons)


def enable():
    global PKG
    if extension_enabled():
        PKG = EXTENSION
        return EXTENSION
    prefs = bpy.context.preferences
    if not any(d.directory == SCRIPTS for d in prefs.filepaths.script_directories):
        d = prefs.filepaths.script_directories.new()
        d.directory = SCRIPTS
    bpy.utils.refresh_script_paths()
    addon_utils.modules_refresh()
    mod = addon_utils.enable('sollumz_dev', default_set=True, handle_error=None)
    if mod is None:
        raise RuntimeError('Sollumz failed to enable')
    PKG = 'sollumz_dev'
    return mod
