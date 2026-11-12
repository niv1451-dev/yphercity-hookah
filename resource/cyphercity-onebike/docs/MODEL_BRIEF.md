# One Bike e-bike: 3D model brief (GTA V / FiveM add-on)

**Goal: an exact 1:1 replica of the real bike.** It is a 20" × 4.0 fat-tire folding electric bicycle
in the "One Bike" black-and-yellow style. Every visible part, decal and proportion should match the photos.

- Main reference: [`reference.jpg`](reference.jpg).
- More photos and real measurements are in the [Reference pack](#reference-pack) section below.

## What I need from you

| File | Notes |
|---|---|
| `onebike.yft` | Model name must be exactly `onebike` |
| `onebike_hi.yft` | High-detail version |
| `onebike.ytd` | All textures |
| Source file (`.blend` or `.z3d`) | So it can be adjusted later |

The meta files are already written: `data/vehicles.meta` and `data/carvariations.meta` in the resource.

## Vehicle setup

- **Type: bicycle (`VEHICLE_TYPE_BICYCLE`).** The rider pedals, and there is one seat.
  The rear passenger cushion is decoration only.
- **Layout: `LAYOUT_BICYCLE_MOUNTAIN`.** Physics and sound come from the vanilla `inductor`, the game's own electric bike.
- **Skeleton: rig it like the vanilla `inductor`**, with the same bone names and hierarchy:
  - Body: `chassis`, `chassis_lowlod`, `bodyshell`, `chassis_dummy`
  - Seat: `seat_f` on the main saddle
  - Pedalling: `crank`, `pedal_l`, `pedal_r`.
    These animate, so put the pivots exactly on the bottom-bracket axle and on each pedal spindle.
  - Steering: `forks_u`, `forks_l`, `handlebars`, `hbgrip_l`, `hbgrip_r`, `dials`
  - Wheels: `wheel_lf`, `wheel_lr`, `swingarm`, plus the `wheelmeshbk_*` bones as in `inductor`
  - Light: `headlight_l`

## Parts to model, from the photo

- **Frame:** folding frame with its hinge and clamp, glossy black, with yellow diagonal stripe decals and the "One Bike" script logo.
- **Rear suspension:** yellow coil-over shock between the frame and the swingarm. The swingarm moves with `wheel_lr`.
- **Front:** black telescopic suspension fork with yellow clamps and guards, and a black front fender.
- **Battery:** black box on the seat tube, with yellow stripes and a small LED indicator.
- **Wheels:** black 6-spoke mag rims with a yellow stripe on the rim, fat knobby tyres, and front and rear disc brakes.
- **Drivetrain:** crankset with a yellow-black chainguard (crank sticker), chain, rear derailleur, cassette and pedals.
- **Rear rack:** yellow tubular rack with a long black cushion (with "One Bike" logo) and a rear fender.
- **Cockpit:** folding stem, riser handlebar with yellow accents, black grips with yellow ends,
  brake levers and cables, a round LCD display (on the `dials` bone) and a phone holder.
- **Front bag:** black bag on the stem.
- **Lights:** a headlight (`headlight_l`) and a red rear light under the rack (visual).
- **Reflectors:** white reflectors on both wheels.
- **Optional:** make the front bag and the phone holder extras (`extra_1`, `extra_2`) so they can be toggled.

## Materials and paint slots

| Part | Material |
|---|---|
| Frame and the black body parts | Paint 1 (primary). The default colour is 0 (black) |
| Yellow parts (rack, shock spring, fork clamps, accents) | Paint 2 (secondary). The default colour is 88 (yellow) |
| Rims | Wheel colour |
| Stripes, logos, `onebike.co.il` text | Decal or badge material, with textures in `onebike.ytd`. Recreate them sharp, not blurred from the photo |
| Tyres | Tyre shader |
| Headlight | Emissive light material |

## Technical limits

- **LODs:** L0, L1, L2 and a low LOD, plus `onebike_hi.yft`.
- **Polygons:** keep the triangle count reasonable for a bike: tens of thousands at L0, not hundreds of thousands.
- **Textures:** 2048 × 2048 at most.
- **File sizes:** keep `onebike.ytd` and each `.yft` under 16 MB, to avoid FiveM's oversized-asset warning.
- **Collisions:** simple bounds on the right bones (chassis and wheels).
- **Test:** spawn `onebike` in FiveM and check pedalling, steering, suspension and the headlight.
  The server must run game build 2802 or newer.

## Reference pack

Extra photos (to be added by the owner):

1. Full side view, left side: camera at hub height, straight at the bike
2. Full side view, right side
3. Straight from the front
4. Straight from the back
5. From above
6. Close-ups: every decal and logo, the display, rims, crank and chainguard, the rear shock, fork clamps and the folding hinge

Real measurements (to be filled in by the owner):

| Measurement | Value |
|---|---|
| Overall length | ___ cm |
| Wheelbase (front axle to rear axle) | ___ cm |
| Ground to top of handlebar | ___ cm |
| Ground to top of main saddle | ___ cm |
| Ground to top of rear cushion | ___ cm |
| Handlebar width | ___ cm |
| Tyre size (printed on the tyre) | ___ |
