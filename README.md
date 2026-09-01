# Couch Arena

A 3D split-screen arena shooter for Windows, for two to four people on one
couch and one screen. Built with [Godot 4.7](https://godotengine.org).

Players join by pressing a button on any connected controller, and the screen
re-partitions itself as they come and go. There is no lobby to back out to and
no menu to navigate — plug in a pad, press A, you are in the match.

![Four-player split screen](docs/split-screen.png)

## Status

Early, but the core loop works end to end: join, move, aim, shoot, kill,
respawn, score — now with rigged, animated characters rather than capsules,
one skin per player. The screenshot above is a real frame rendered from the
project, not a mockup.

It has **not** been played on real hardware with real controllers. Movement
feel, camera comfort and controller compatibility are all unverified, and that
is the next job. See [docs/ROADMAP.md](docs/ROADMAP.md).

All art is CC0 — see [docs/ASSETS.md](docs/ASSETS.md) for sources and the
import pipeline.

## Controls

| Action | Gamepad | Keyboard |
| --- | --- | --- |
| Join | `A` or `Start` | `Enter` |
| Move | Left stick | `W` `A` `S` `D` |
| Aim | Right stick | Arrow keys |
| Fire | Right trigger, `RB`, or `A` | `Space` |

Up to four gamepads are supported, plus one keyboard seat. The keyboard seat
exists so the game can be launched and checked without controllers attached;
it is not meant as a way to play seriously.

## Running it

Install [Godot 4.7](https://godotengine.org/download) — a single executable,
no installer and no SDK. Then either open `project.godot` in the editor and
press F5, or from the command line:

```bash
godot --path .
```

## Exporting for Windows

In the editor: **Project → Export**, add a Windows Desktop preset, install the
export templates when prompted, and export. The result is a standalone `.exe`
plus a `.pck` data file.

## Development

```bash
# Headless test suite: geometry, input maths, and the join/spawn/score path.
godot --headless --path . --script res://tests/run_tests.gd

# Re-render docs/split-screen.png from a live four-player match.
xvfb-run godot --path . --rendering-driver opengl3 \
    --rendering-method gl_compatibility --script res://tests/screenshot.gd
```

The screenshot script is how this project checks that rendering actually works
without a physical machine in the loop; on Windows or macOS, drop `xvfb-run`
and the renderer flags.

Further reading: [docs/DESIGN.md](docs/DESIGN.md) for how the code fits
together, [docs/ASSETS.md](docs/ASSETS.md) for art sources and import traps,
[docs/ROADMAP.md](docs/ROADMAP.md) for the plan, and [CLAUDE.md](CLAUDE.md) for
the constraints worth knowing before editing.

## Licence

Not yet chosen.
