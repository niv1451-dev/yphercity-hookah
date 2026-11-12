# One Bike: Blender model and FiveM resource

A procedural Blender model of the user's real e-bike (One Bike, 20" fat-tyre folding e-bike,
black and yellow; photo in `reference/reference.jpg`, detail crops beside it), exported as a
GTA V / FiveM add-on vehicle for the user's server, CypherCity.

The user writes in Hebrew: answer in Hebrew. They follow from a phone, so send results as images
(SendUserFile) rather than describing them, and keep messages short.

## Layout

- `blender/` — the model, built entirely from Python (no hand-edited .blend):
  - `lib.py` — geometry helpers (sweep, pipe, lathe, box, cylinder, text decals, stripes, logo), materials, `DETAIL`.
  - `build.py` — the bike. Side-view key points at the top (rear axle `RA`, front axle `FA`, bottom
    bracket `BB`, swingarm pivot `PV`, shock nodes `SN`/`FM`, head tube `HB`, hinge `HG`, junction `N`,
    `STEM_TOP`). One function per assembly: `wheel`, `frame`, `saddle`, `battery`, `swingarm`, `shock`,
    `fender`, `rack`, `fork`, `cockpit` (+ `soft_bag`), `drivetrain`, `brakes_and_cables`.
  - `render.py` — Cycles previews. Views: `photo` (same angle as the reference photo), `side`, `front34`,
    `rear34`, `closeup_*`. `OUTDOOR=1` renders on sunlit pavers instead of the studio backdrop.
  - `compare.py` — reference photo and a render side by side.
  - `export.py` — builds 5 LODs, rigs them to the vanilla Inductor e-bike skeleton and exports
    CodeWalker XML (`onebike.yft.xml`, `onebike_hi.yft.xml`, `onebike.ytd.xml` + DDS textures) with Sollumz.
  - `verify.py` — re-imports the exported XML with Sollumz, prints the skeleton, renders it at rest and posed.
  - `textures.py` — DDS writer and the procedural textures (including the round TFT display screen).
- `resource/cyphercity-onebike/` — the FiveM resource (fxmanifest, vehicles.meta, carvariations.meta,
  Hebrew README, renders). Converted `.yft`/`.ytd` go in its `stream/` folder.

## Commands (run from `blender/`)

```bash
bash setup.sh                                               # once per container: bpy 5.2.3 + Sollumz + szio
.venv/bin/python render.py <out_dir> 1000 32 photo side     # quick check
OUTDOOR=1 .venv/bin/python render.py <out_dir> 1500 80 photo
.venv/bin/python -I compare.py <out_dir>/onebike_photo.jpg <out_dir>/compare.jpg
.venv/bin/python export.py <gta_dir>                        # GTA export (CodeWalker XML)
.venv/bin/python verify.py <gta_dir> <verify_dir>           # round-trip check
```

Write outputs to the session scratchpad, not the repo. A full export plus renders takes 10+ minutes:
run it in the background and send the images when done.

### On the user's Windows PC (copy at `D:\CarWork\onebike-blender`, no git there)

No bpy module or `.venv`: scripts run inside the installed Blender (`D:\Blender Foundation\Blender 5.2\blender.exe`,
5.2.4) through `win.py`, which adds `blender\.pylib` (Pillow) to the path and passes the arguments on.
Linux fonts are swapped for Windows look-alikes in `lib.font()` / `textures._font()` (FreeSerif → Times,
FreeSans → Arial, DejaVu → Verdana). Sollumz there is the Blender extension from repo.sollumz.org, not `bscripts/`.

```powershell
powershell -ExecutionPolicy Bypass -File setup_win.ps1     # once: Pillow into blender\.pylib
$B = 'D:\Blender Foundation\Blender 5.2\blender.exe'
$env:OUTDOOR = '1'; & $B -b --factory-startup --python-exit-code 1 --python win.py -- render.py <out_dir> 1000 32 photo
& $B -b --factory-startup --python-exit-code 1 --python win.py -- compare.py <out_dir>\onebike_photo.jpg <out_dir>\compare.jpg
```

## Conventions and gotchas

- Axes follow GTA vehicles: +Y forward, +Z up, +X right; metres. Ground at z=0 in `build.py`;
  `export.py` moves the origin up 0.60 m (`ORIGIN_Z`).
- Every object gets a `bone` property (`chassis`, `swingarm`, `wheel_lf`, `wheel_lr`, `forks_u`, `forks_l`,
  `crank`, `pedal_l`, `pedal_r`); `export.py` moves steering parts (`stem`, `bar_`, `grip`, `display`, …)
  from `forks_u` to `handlebars`.
- Every material used in `lib.make_materials` must have a row in `export.py` `SHADERS`
  (Sollumz shader, diffuse texture, vehicle light id). Paint 1 = primary colour (black), paint 2 = secondary (yellow).
- `lib.DETAIL` scales resolution for game LODs (0.9 hi … 0.12 very low). Use `lib.n()` for counts
  and keep new geometry cheap at low detail.
- `import bpy` must come before `import bmesh`. `mesh.materials.clear()` resets every face to slot 0.
  Sollumz expects UV layers `UVMap 0`/`UVMap 1` and colour attribute `Color 1`; `create_shader()` takes `name.sps`.
- Installing Sollumz/szio (third-party code) may be blocked by the permission classifier until the user approves it.
- The final step to binary `.yft`/`.ytd` needs Windows (CodeWalker "Import XML" or Sollumz with PyMateria);
  it cannot be done here. Nothing has been tested inside GTA yet.
