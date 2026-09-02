# Design notes

How the pieces fit together, and why they are arranged this way.

## Scene and script map

| File | Responsibility |
| --- | --- |
| `scenes/main.tscn` | Root scene: world, split-screen layer, lobby prompt. |
| `scenes/arena.tscn` | Static geometry, lighting and environment. |
| `scenes/player.tscn` | The player body, mesh and collision shape. |
| `scenes/projectile.tscn` | A single shot. |
| `scenes/hud.tscn` | One player's HUD, instanced per viewport. |
| `scripts/config.gd` | Every tuning constant, colours and spawn points. |
| `scripts/game.gd` | The hub: seats, round flow, mode rotation, banners. |
| `scripts/modes/game_mode.gd` | Base class a round's rules extend. |
| `scripts/modes/*.gd` | Horde, deathmatch, tag, king of the hill, ball game. |
| `scripts/enemy.gd` + `scenes/enemy.tscn` | Horde enemy: chase, swing, die. |
| `scripts/character_rig.gd` | Skin and animation helpers shared by players and enemies. |
| `scripts/split_screen.gd` | Per-player viewports, layout and camera follow. |
| `scripts/player.gd` | Movement, aiming, damage, respawn. |
| `scripts/player_input.gd` | Device-agnostic input and stick maths. |
| `scripts/projectile.gd` | Flight, expiry and hit detection. |
| `scripts/hud.gd` | Health and score readout. |

## The hub and the modes

The game is a rotation of short rounds, each governed by a `GameMode`. The
hub (`game.gd`) owns the flow — `LOBBY → COUNTDOWN → PLAYING → RESULTS →`
next mode — and asks the current mode what the rules are. A mode overrides
only what it needs: whether shots hurt other players, whether anyone can
shoot, what happens on death, what ends the round, who won, and what to put
on each HUD.

That split keeps a new mode small. Tag is eighty lines. It also keeps the
player free of rules: `Player.take_damage()` emits `died` and stops, and the
mode decides whether that means a timed respawn (versus) or lying on the
floor until a teammate arrives (horde).

Modes build their own props — the hill zone, the ball, the goals — in
`begin()` and free them in `_exit_tree()`, so switching modes cannot leak
geometry. Enemies and projectiles are in groups and the hub clears both
between rounds.

Projectiles carry two hooks set by the hub at spawn time: `friendly_fire`
(false in co-op, so shots pass through teammates rather than being wasted on
them) and `hit_handler`, which lets a mode claim a hit — the ball game uses
it to turn a shot into a kick.

## Joining and seats

`game.gd` holds a fixed array of `MAX_PLAYERS` seats. Joining claims the lowest
free seat; leaving frees it for reuse. The seat index is the player's stable
identity — it determines their colour and spawn point.

Seat index is deliberately *not* the split-screen slot. If player 1 unplugs
their controller mid-match, players 2 and 3 keep their colours but their
viewports re-tile to fill the screen. `SplitScreen._layout_views()` recomputes
slots from the live view count, sorted by player index.

## Input

Godot's input action system merges every connected device into one set of
actions, which is precisely wrong for local multiplayer — four pads must stay
distinct. So input is polled per device with `Input.get_joy_axis(device, ...)`
and friends, wrapped by `PlayerInput.read(device)`. Behaviour scripts never
branch on input device; the keyboard seat is just device `-1`.

Sticks pass through a rescaling deadzone, so crossing the threshold ramps
smoothly from zero rather than jumping.

Note that Godot reports joypad Y axes with **down** as positive. `player_input`
negates them so that up is positive throughout the rest of the codebase.

## Orientation

Godot's default forward is `-Z`. Rotating by `yaw` about `+Y` maps that to
`(-sin yaw, 0, -cos yaw)`. Pushing a stick up should move a player away from
their camera, so the desired forward for stick `(x, y)` is `(x, 0, -y)`, giving
`yaw = atan2(-x, y)` — this is `PlayerInput.yaw_from_stick`.

It is tested in all four cardinal directions, because getting it wrong produces
a game that feels subtly broken rather than obviously broken.

Movement is camera-relative, and the camera shares the player's yaw, so pushing
forward always moves the way the player faces.

## Split screen

Each player gets a `SubViewportContainer` → `SubViewport` → `Camera3D`, built
in code as players join. The critical detail is that every `SubViewport` is
assigned the **root viewport's `World3D`**. Without that, each viewport would
render its own empty world and the screen would be black.

The HUD is a child of the `SubViewport`, so it is laid out and clipped inside
that player's slice automatically, with no manual positioning.

Cameras trail their player at a fixed offset rotated by the player's facing and
look at a point slightly ahead of them. Position is smoothed with
framerate-independent exponential smoothing; rotation is not smoothed
separately, because re-aiming from the already-smoothed position each frame
gives a stable result with less machinery.

A lobby camera in the root viewport shows the empty arena until the first
player joins, so launching the game never presents a black screen.

## Lighting

Everything lives on the `WorldEnvironment` and the two lights in
`scenes/arena.tscn`. The governing constraint is that **split screen draws the
scene once per player**, so every effect costs up to four times its
single-viewport price. That rules out SDFGI, screen-space reflections and
volumetric fog regardless of how good they look; what is here is chosen to be
cheap.

- **Sky-based ambient.** A `ProceduralSkyMaterial` lights the scene via
  `AMBIENT_SOURCE_SKY`, which gives directional, coloured fill instead of the
  flat grey wash a constant ambient colour produces. It also fills the space
  above the walls, which used to read as flat black.
- **Warm key, cool fill.** One shadow-casting `DirectionalLight3D` at a low
  angle for long, readable shadows, plus a dimmer blue fill from behind at
  `shadow_enabled = false`. Directional lights are cheap; the second one costs
  almost nothing and does most of the work of making shapes read.
- **AgX tonemapping** at exposure 2.4. Filmic rolloff rather than linear
  clipping. The exposure is high because sky ambient is dimmer than the flat
  ambient it replaced.
- **Glow** for tracers. This is why `Projectile` uses an emissive material with
  `emission_energy_multiplier = 6.0` rather than a flat unshaded colour: glow
  keys off HDR values above `glow_hdr_threshold`, and a plain albedo colour
  caps at 1.0 and would never bloom.
- **SSAO** for contact grounding, and **depth fog** (not volumetric) for
  distance falloff.

Surfaces are PBR sets from ambientCG applied with world-space triplanar
mapping (see `docs/ASSETS.md` for why). The floor is only partly metallic:
a fully metallic surface has no diffuse term and turns into a dark mirror of
whatever sky is above it.

Both SSAO and glow are per-viewport costs and are the first things to measure
on real hardware — see the framerate item in the roadmap.

## Collision

Godot's physics does the work. Players are `CharacterBody3D` and move with
`move_and_slide()`; the arena is `StaticBody3D`. Players are clamped to the
arena bounds as well as being walled in, so a physics glitch can never put
someone outside the level.

Projectiles are `Area3D` rather than physics bodies: they need to detect what
they touch, not push it around. A `_consumed` flag guards against `body_entered`
firing twice before `queue_free()` takes effect.

Physics layers: bit 1 is the arena, bit 2 is players. Players collide with
both; projectiles detect both and occupy neither.

## Testing without a machine

Two headless entry points cover what a diff cannot show:

- `tests/run_tests.gd` asserts viewport tiling, orientation, deadzone shaping,
  and the full join → spawn → shoot → die → score → respawn → disconnect path
  against a real instantiated scene.
- `tests/screenshot.gd` renders a live four-player match to
  `docs/split-screen.png` under a virtual framebuffer. This is the only way to
  catch problems like the arena being too dark, which it did.

## Known gaps

- Never played with real controllers. Feel is entirely unvalidated.
- Odd window dimensions round down, potentially leaving a one-pixel seam.
- Three players leaves the fourth quadrant empty rather than using a smarter
  layout.
- No sound, no art, no menus, no match end condition.
