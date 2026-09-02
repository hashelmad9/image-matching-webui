# Working on Couch Arena

Read this before making changes. It captures the constraints that are easy to
get wrong and expensive to discover late.

## What this project is

A local-multiplayer ("couch co-op") 3D split-screen arena shooter for Windows,
built with Godot 4.7 and GDScript.

## Verify your work

This project can be tested and even *rendered* without a display, so there is
no excuse for shipping unverified changes:

```bash
# Headless tests: viewport tiling, orientation maths, join/spawn/score wiring.
godot --headless --path . --script res://tests/run_tests.gd

# Renders a real four-player frame to docs/split-screen.png. Look at it.
VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json \
    xvfb-run godot --path . --script res://tests/screenshot.gd
```

Both must pass before committing. If you touch anything visual — lighting,
camera framing, arena layout, HUD — re-render and actually open the image. The
first version of this arena was too dark to play, and only looking at the
render caught it.

On Linux, rendering needs `xvfb` and Mesa's software Vulkan driver:

```bash
apt-get install -y xvfb mesa-vulkan-drivers vulkan-tools libgl1-mesa-dri
```

Render through Forward+, not the compatibility renderer — compatibility has no
SSAO and would misrepresent the shipping look. Be aware that software Vulkan
**does not draw directional shadows**, so the render understates reality and
shadow tuning can only be judged on real hardware. See `docs/ASSETS.md`.

## Rules of the road

**Do not write Godot API calls from memory.** This project targets Godot 4.7,
and the API moves between versions. The authoritative reference for the exact
build is the engine itself:

```bash
godot --headless --dump-extension-api   # writes extension_api.json
```

Grep that for real class names, method signatures and enum values.

**`.tscn` files do not support `#` comments.** The parser stops reading a
node's properties at the first `#` line and silently keeps defaults for the
rest. Explanations go in `docs/`, not the scene file.

**Tuning values live in `scripts/config.gd`.** Balance and feel changes belong
there, not scattered through behaviour scripts.

**Input is polled per device, never through the action map.** Godot's input
actions merge every controller into one, which is exactly wrong for local
multiplayer. `PlayerInput.read(device)` is the only way input should be read.

**Player index is not the split-screen slot.** `Player.index` is stable
identity — it picks the colour and spawn point and survives other players
leaving. The viewport slot is recomputed from the live player count in
`SplitScreen._layout_views()`.

**SubViewports must share the root `World3D`.** That is what makes four
cameras look into one arena instead of four empty copies of it. If a viewport
renders black, check `world_3d` first.

**Collision belongs to the physics engine.** Players are `CharacterBody3D` and
use `move_and_slide()`; the arena is `StaticBody3D`. Do not hand-roll collision
resolution — an earlier version of this game did, and it was strictly worse.

**Only CC0 art enters this repository,** and every asset is recorded in
`docs/ASSETS.md`. That file also documents the import traps — chiefly that
`get_aabb()` and bone rests both report the wrong size for a rigged model, so
scale must be calibrated against a rendered reference, never a measurement.

**Rules live in `scripts/modes/`, not in the player.** `Player` reports a
death and stops; the mode decides what it means. Adding a mode means
subclassing `GameMode` and overriding only what differs — see DESIGN.md. A
mode that spawns props must free them in `_exit_tree()`.

**Physics queries only in `_physics_process`.** `direct_space_state` is locked
outside physics callbacks; a ray cast from `_process` errors. The camera
follow lives in `_physics_process` for exactly this reason.

**A dead player stays visible for `CORPSE_SECONDS`.** Tests that assert a
body vanishes on death are asserting the wrong contract.

**A projectile must only be consumed once.** `Projectile` guards this with the
`_consumed` flag, because `body_entered` can fire more than once before
`queue_free()` takes effect.

## Testing what cannot be seen

Nobody reviewing a diff can tell whether the camera ended up behind the player
or inside their head. Geometry, layout and wiring are covered by the headless
suite, and new geometry should come with tests too.

What the tests genuinely cannot cover is how the game *feels* — movement
weight, camera comfort, whether a fight is fun, and whether real controllers
map correctly. Only a human with a gamepad can answer those. Say so plainly
rather than implying it was checked.
