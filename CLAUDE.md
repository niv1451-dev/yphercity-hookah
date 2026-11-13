# One Bike: Blender model and FiveM resource

## שפה - הוראה קבועה של המשתמש (חלה על כל העבודה בפרויקט)

מעכשיו, עברית היא שפת התקשורת היחידה שלך איתי.

חובה לפעול לפי הכללים הבאים בכל שיחה ובכל משימה:

1. כל ההסברים, ההודעות, השאלות, העדכונים ודוחות ההתקדמות יהיו בעברית בלבד.
2. לפני ביצוע פעולה, הסבר בעברית מה אתה עומד לעשות.
3. במהלך העבודה, עדכן אותי בעברית מה ביצעת ומה השלב הבא.
4. אם נתקלת בשגיאה, הסבר אותה בעברית והצע פתרון.
5. בסיום כל משימה, הצג סיכום מלא בעברית.
6. אל תחזור לאנגלית לאחר מספר הודעות.
7. אם אתה צריך להשתמש במונחים טכניים, פקודות, שמות קבצים או קוד באנגלית, השאר אותם באנגלית והסבר את משמעותם בעברית.
8. אל תבקש ממני שוב להגדיר את השפה.

חשוב: ההוראה הזאת קבועה וחלה על כל העבודה שלנו בפרויקט.
(גם התיאור הקצר של כל פעולה, כיתובי תמונות, הערות חדשות בקוד והודעות שמירה - בעברית.)

## הגלגלים במשחק - נפתר ב-13 בנובמבר 2026 (הסעיף באנגלית על הגלגלים בהמשך הקובץ ישן)

נבדק בצילומים במשחק: האופניים עומדים על הקרקע, שני הגלגלים במקום, הרוכב יושב, הצמיג נקי.
מה היה צריך, לפי השוואה לאופניים של המשחק עצמו (חשמליות "פאוורסרג'" ו"אינדקטור"):
1. כל הגוף (כל חלק שאינו גלגל) יוצא כצורה מעוותת אחת: כל נקודה קשורה לעצם שלה במשקל מלא, והצורות
   שמורות בקואורדינטות הכלליות של האופניים. כשהגוף היה חלקים קשיחים, המשחק צייר את הגלגלים בכפל המרחק.
2. הגלגלים נשארים חלקים נפרדים, יחסית למרכז שלהם, וכל חלקי הגלגל בחומר הצמיג של המשחק.
3. מיפוי הטקסטורה בגלגלים בתחום 0 עד 1, יחסית למרכז הגלגל.
4. אף חלק בקובץ לא עובר כ-65 אלף נקודות. הסוליה מחולקת לשני חומרים זהים (אמצע וצד), אחרת המשחק
   מחבר נקודות לא נכונות וזה נראה כמו קוצים.
5. טבלת המיקום של חלקי הפיזיקה מועתקת גם לקובץ המפורט, והחוזק לשבירה של כל חלק הוא 100 כמו במקור.
כל התיקונים נמצאים בסקריפט הייצוא. כלי הבדיקה במשחק ובדיקות ההשוואה נמצאים בתיקיית הבדיקות.
בסקריפט הבדיקה במשחק: לקחת את השחקן מחדש לפני כל שימוש, כי המשחק מחליף אותו בסיום הכניסה.

A procedural Blender model of the user's real e-bike (One Bike, 20" fat-tyre folding e-bike,
black and yellow; photo in `reference/reference.jpg`, detail crops beside it), exported as a
GTA V / FiveM add-on vehicle for the user's server, CypherCity.

The user writes in Hebrew: answer in Hebrew. They follow from a phone, so send results as images
(SendUserFile) rather than describing them, and keep messages short.

## Layout

- `blender/` — the model, built entirely from Python (no hand-edited .blend):
  - `lib.py` — geometry helpers (sweep, pipe, lathe, box, cylinder, text decals, stripes, logo), materials, `DETAIL`.
  - `build.py` — the bike. Side-view key points at the top, all measured on the photo through the solved
    camera (rear axle `RA`, front axle `FA`, crank axle `BB`, swingarm pivot `PV`, shock eyes `SN`/`FM`,
    hinge `HG`, main tube `MT_A`→`HT_MID`, seat tube `SEAT_A/B`, steering axis `HEAD` = 20° through `FA`
    via `on_axis(z)`, crowns, `STEM_*`, `BAR`, `BAG`, `CUSHION`, `BAT_A/B`, `TYRE_R`, `GROUND_Z`).
    One function per assembly: `wheel`, `frame` (main tube, hinge, down post, arch, seat tube, lower housing),
    `saddle`, `battery`, `swingarm`, `shock`, `fender`, `rack` (+ `cushion`), `fork` (+ `crown`),
    `cockpit` (+ `soft_bag`), `drivetrain`, `brakes_and_cables`.
  - `render.py` — Cycles previews. Views: `photo` (same angle as the reference photo), `side`, `front34`,
    `rear34`, `closeup_*`. `OUTDOOR=1` renders on pavers lit by Blender's bundled `courtyard.exr` HDRI.
  - `match.py` — renders through the camera solved from the photo (`reference/camera.json`), front end
    steered 31.6° like the photo, and writes overlays: `match_over.jpg` (model on the photo), `match_blend.jpg`,
    `match_outline.jpg`, `match_side.jpg`. This is the 1:1 check: geometry is right when the model sits on the
    photo. Add `photo` as 4th argument for HDRI lighting with the floor shadow.
  - `photo_match/` — `yellow_mask.py` + `calib.py` solved the camera from the two yellow rim stripes;
    `pick.py ruler|conv|convs` makes pixel-ruler crops and turns photo pixels into metres on a bike plane
    (`convs` = the steered front plane). Measure from the photo this way before changing geometry.
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
& $B -b --factory-startup --python-exit-code 1 --python win.py -- match.py <out_dir> 32 0.6 [photo]
$env:PYTHONPATH = '.pylib'; & '<blender>\5.2\python\bin\python.exe' photo_match\pick.py conv 0 1300,835
& $B -b --factory-startup --python-exit-code 1 --python win.py -- compare.py <out_dir>\onebike_photo.jpg <out_dir>\compare.jpg
```

## Conventions and gotchas

- Photo matching: every dimension comes from `reference/camera.json`. Its focal length is weakly determined
  (a 28.5 mm solve fits almost as well as the 23.6 mm one), so do not re-solve it: the geometry was measured
  with this file and would drift. Silhouette edges belong to the near or far face, not the centre plane: convert
  a top edge seen from above on the far plane (x < 0) and a bottom edge on the near plane (x > 0). The tyre bottom
  is the near side of the tread, which is why `TYRE_R` is 0.295 and the road (`GROUND_Z`) sits 3.8 cm up.

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
- The final step to binary `.yft`/`.ytd` needs Windows. On the user's PC: export without `--factory-startup`
  (Sollumz extension), then `powershell -ExecutionPolicy Bypass -File cw_convert.ps1 <gta_dir>` makes the binaries
  with CodeWalker.Core (`D:\CodeWalker\CodeWalker30_dev46`). Use these, not Sollumz's own binary output.
- In game (home FiveM server, resource `[selected_cars]\cyphercity-onebike`): `gametest/` holds the photo test
  (`run_shots.ps1` restarts the server and screenshots each view from `zz_onebike_test.lua`, which must be listed
  in the server's fxmanifest while testing) and read-only CodeWalker inspectors that compare our `.yft` with
  vanilla `powersurge.yft` / `inductor.yft`. Before any restart, check / write `D:\FiveMServer\server_test.lock`
  (another session tests there too).
- Wheels in game: `export.py` patches Sollumz twice. Physics children get min breaking impulse 100. The
  fragment bone-transform set is written as identity like vanilla (Sollumz writes model-space matrices, which
  made the game draw and place the wheels at about twice their offset). The second patch is not yet confirmed in game.
