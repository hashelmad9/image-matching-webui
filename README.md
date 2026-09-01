# Couch Arena

A 3D split-screen arena shooter for Windows, for two to four people on one
couch and one screen. Built in Rust with [Bevy](https://bevyengine.org).

Players join by pressing a button on any connected controller, and the screen
re-partitions itself as they come and go. There is no lobby to back out to and
no menu to navigate — plug in a pad, press A, you are in the match.

## Status

Early. The core loop works end to end: join, move, aim, shoot, kill, respawn,
score. It has not yet been played on real hardware — see
[docs/ROADMAP.md](docs/ROADMAP.md) for what is next.

## Controls

| Action | Gamepad | Keyboard |
| --- | --- | --- |
| Join | `A` or `Start` | `Enter` |
| Move | Left stick | `W` `A` `S` `D` |
| Aim | Right stick | Arrow keys |
| Fire | Right trigger, `RB`, or `A` | `Space` |

Up to four gamepads are supported, plus one keyboard seat. The keyboard seat
exists so the game can be launched and checked without any controllers
attached; it is not intended as a way to play seriously.

## Building

Requires [Rust](https://rustup.rs). On Windows, the MSVC toolchain is the
supported target:

```bash
git clone <this repo>
cd couch-arena
cargo run --release
```

The first build compiles Bevy from source and takes a while. Later builds are
fast. Debug builds are playable because dependencies are optimised even in the
dev profile — see the `[profile.dev]` section of `Cargo.toml`.

To ship a build, `cargo build --release` produces a self-contained
`target/release/couch_arena.exe` with no runtime dependencies and no console
window.

### Building on Linux

Bevy links against system libraries that are not installed by default:

```bash
sudo apt-get install libwayland-dev libasound2-dev libudev-dev libxkbcommon-dev pkg-config
```

## Development

```bash
cargo check --target x86_64-pc-windows-gnu   # verify the shipping target
cargo test                                   # geometry and input unit tests
cargo clippy --target x86_64-pc-windows-gnu  # lints; the tree is warning-clean
```

Further notes: [docs/DESIGN.md](docs/DESIGN.md) for how the code fits together,
[CLAUDE.md](CLAUDE.md) for the constraints worth knowing before editing.

## Licence

Not yet chosen.
