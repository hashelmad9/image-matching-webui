# Working on Couch Arena

Read this before making changes. It captures the constraints that are easy to
get wrong and expensive to discover late.

## What this project is

A local-multiplayer ("couch co-op") 3D split-screen arena shooter for Windows,
written in Rust with Bevy. No game editor is involved: every scene, level and
entity is defined in code under `src/`.

## Build and verify

The game targets Windows, but development happens on whatever machine you are
on. Two verification paths exist and both matter:

```bash
# Type-check against the shipping target. This is the check that counts.
cargo check --target x86_64-pc-windows-gnu

# Unit tests for the pure geometry and input maths. Runs natively.
cargo test

# Lints. The project is warning-clean; keep it that way.
cargo clippy --target x86_64-pc-windows-gnu
```

On Linux, `cargo test` needs system libraries that Bevy links against:

```bash
apt-get install -y libwayland-dev libasound2-dev libudev-dev libxkbcommon-dev pkg-config
```

To produce a Windows executable, build on Windows with the MSVC toolchain:

```bash
cargo build --release          # target/release/couch_arena.exe
```

## Rules of the road

**Bevy's API changes between minor versions.** This project is pinned to Bevy
0.19. Do not write Bevy code from memory — the crate source is the reference,
and it ships its own examples:

```
~/.cargo/registry/src/*/bevy-0.19.1/examples/
```

`examples/3d/split_screen.rs` and `examples/input/gamepad_input.rs` cover the
two mechanisms this game is built on. Several things were renamed in 0.19 and
will not be what you remember: events are read with `MessageReader`, not
`EventReader`; `Timer::finished()` is `is_finished()`; ambient light is the
`GlobalAmbientLight` resource; `TextFont::font_size` takes `FontSize::Px(..)`.

**Tuning values live in `src/config.rs`.** Balance changes belong there, not
scattered through systems.

**Nothing leaves the ground plane.** Players and projectiles are constrained to
a fixed height, and collision is deliberately 2D (XZ) as a result. If you add
verticality, `player::push_out_of_box` and `combat::hits_player` both need
revisiting.

**A projectile must be despawned at most once per frame.** Movement, expiry and
both collision checks deliberately live in the single `update_projectiles`
system for this reason. Splitting them reintroduces double-despawn warnings.

**Player index is not the split-screen slot.** `Player::index` is stable
identity — it picks the colour and spawn point and survives other players
leaving. The viewport slot is recomputed each frame from the live player count
in `camera::assign_viewports`.

## Testing what cannot be seen

Nobody reviewing a diff can tell whether a camera ended up behind the player or
inside their head. The pure functions — viewport layout, stick-to-yaw
conversion, collision resolution, hit tests — are unit tested, and new geometry
should come with tests too. Anything requiring a window and a gamepad has to be
verified by a human actually playing it; say so plainly rather than implying it
was checked.
