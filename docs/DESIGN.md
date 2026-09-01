# Design notes

How the pieces fit together, and why they are arranged this way.

## Module map

| Module | Responsibility |
| --- | --- |
| `main.rs` | Window setup and plugin registration. |
| `config.rs` | Every tuning constant, plus per-player colours and spawn points. |
| `arena.rs` | Static geometry: floor, boundary walls, cover, lighting. |
| `player.rs` | Joining and leaving, input abstraction, movement, respawn. |
| `camera.rs` | One camera per player, viewport layout, follow behaviour. |
| `combat.rs` | Firing, projectile flight, hit resolution, scoring. |
| `hud.rs` | Per-player HUD and the lobby prompt. |

Each is a Bevy plugin, registered in `main.rs`. Cross-module coupling is
deliberately one-directional: `camera` and `hud` react to players appearing via
`Added<T>` queries rather than the player code reaching out to spawn cameras.
This means a camera and HUD may appear a frame after the player does, which is
imperceptible and buys clean module boundaries.

## Joining and seats

`Roster` holds a fixed array of `MAX_PLAYERS` optional seats. Joining claims
the lowest free seat; leaving frees it for reuse. The seat index is the
player's stable identity — it determines their colour and spawn point.

Crucially, seat index is *not* the split-screen slot. If player 1 unplugs their
controller mid-match, players 2 and 3 keep their colours but their viewports
re-tile to fill the screen. `camera::assign_viewports` recomputes slots each
frame by sorting live cameras by player index.

## Input

`InputSource` is either a gamepad entity or the single keyboard seat, and
`read_input` normalises both into a `PlayerInput` of two stick vectors and a
fire flag. Systems never branch on input device.

Stick input passes through a rescaling deadzone, so crossing the threshold
ramps smoothly from zero instead of jumping.

## Orientation

Bevy's default forward is `-Z`. Rotating by `yaw` about `+Y` maps that to
`(-sin yaw, 0, -cos yaw)`. Pushing a stick up should move a player away from
their camera, so the desired forward for stick `(x, y)` is `(x, 0, -y)`, giving
`yaw = atan2(-x, y)`. This is `player::yaw_from_stick`, and it is unit tested in
all four cardinal directions because getting it wrong produces a game that
feels subtly broken rather than obviously broken.

Movement is camera-relative, and the camera shares the player's yaw, so pushing
forward always moves in the direction the player faces.

## Cameras

Each player's camera trails them at a fixed offset rotated by their facing, and
looks at a point slightly ahead of them. Position is smoothed with
framerate-independent exponential smoothing; rotation is not smoothed
separately, because re-aiming from the already-smoothed position each frame
gives a stable result with less machinery.

A lobby camera covers the window while no players have joined, so launching the
game shows a title rather than a black screen.

## Collision

There is no physics engine. Everything is on the ground plane at a fixed
height, so collision is 2D and hand-rolled:

- Players versus cover: circle-versus-AABB in XZ, resolved by pushing the
  player to the nearest face. A player somehow inside a box is ejected through
  the shallowest face.
- Players versus arena edge: a position clamp. The boundary walls are purely
  decorative.
- Projectiles versus cover: sphere-versus-AABB, absorbing the shot.
- Projectiles versus players: a radius test in XZ plus a vertical band, which
  approximates the capsule more cheaply and more forgivingly than a sphere.

This is enough for an arena shooter and avoids a large dependency. If the game
ever gains verticality, jumping or physics-driven objects, adopting
[Avian](https://github.com/Jondolf/avian) would be the moment to do it.

## Projectile lifecycle

Movement, expiry, bounds and both collision checks all happen in
`combat::update_projectiles`. This is not an accident of layout: if two systems
could each queue a despawn for the same projectile in one frame, Bevy warns
about despawning a missing entity. Keeping it in one system makes "consumed at
most once" a local, checkable property.

Scoring reads a separate `Query<&mut Score>`. Because it touches a component
disjoint from the victim query, Bevy's access checker allows both, which lets a
killer be credited in the same pass that damages the victim.

## Known gaps

- Nothing has been verified on real hardware with real controllers.
- Odd window dimensions round down, potentially leaving a one-pixel seam
  between viewports.
- Three players leaves the fourth quadrant empty rather than using a smarter
  layout.
- No sound, no art, no menus, no match end condition.
