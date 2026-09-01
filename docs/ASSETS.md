# Assets

Where art comes from, what is already here, and the import traps that cost
time the first time round.

## Licensing rule

**Only CC0 assets enter this repository.** CC0 is public domain: usable
commercially, no attribution required, no licence file to ship, and no risk of
having to tear art out later. Every source below has been checked to be CC0.

Anything under CC-BY, CC-BY-SA or a custom "free for non-commercial" licence
stays out unless the licence is read in full and recorded here first. This
matters more than it looks: mixed licensing is very hard to unpick once art is
threaded through a dozen scenes.

## Already in this repository

| Asset | Source | Licence | Used for |
| --- | --- | --- | --- |
| `assets/characters/characterMedium.fbx` | [Kenney — Animated Characters Survivors](https://kenney.nl/assets/animated-characters-survivors) | CC0 | The player body |
| `assets/characters/animations/{idle,run,jump}.fbx` | same pack | CC0 | Locomotion |
| `assets/characters/*.png` | same pack | CC0 | One skin per player seat |

Four skins ship with that pack, which is exactly `MAX_PLAYERS`, so each seat
reads as a different person. See `Config.PLAYER_SKINS`.

## Verified sources

All confirmed CC0 and reachable without an account.

### 3D models and characters

- **[Kenney](https://kenney.nl/assets)** — the most reliable source going.
  Everything is CC0, downloads are direct zips with no sign-up, and packs ship
  FBX, OBJ and GLB side by side. Relevant packs:
  [Animated Characters Survivors](https://kenney.nl/assets/animated-characters-survivors)
  (rigged, 58-bone skeleton, idle/run/jump, 4 skins),
  [Animated Characters Protagonists](https://kenney.nl/assets/animated-characters-protagonists),
  [Animated Characters Retro](https://kenney.nl/assets/animated-characters-retro),
  [Blaster Kit](https://kenney.nl/assets/blaster-kit) (40 GLB sci-fi weapons,
  scopes, grenades, crates),
  [Prototype Kit](https://kenney.nl/assets/prototype-kit) (greyboxing levels).
- **[Quaternius — Sci-Fi Essentials Kit](https://quaternius.com/packs/scifiessentialskit.html)**
  — 60-70 models: animated robot enemies, textured guns, animated screens,
  crates. CC0, ships FBX/OBJ/glTF. The "Source" version includes shaders
  pre-wired for Godot, which is unusual and worth having.
- **[KayKit](https://kaylousberg.itch.io/kaykit-complete)** — CC0 stylised
  characters, fully rigged, with a separate
  [animation pack](https://kaylousberg.itch.io/kaykit-character-animations)
  carrying 90+ humanoid clips. This is the answer if the Kenney characters'
  three animations prove too thin.

### Textures and lighting

- **[Poly Haven](https://polyhaven.com/textures)** — CC0 PBR texture sets and
  HDRIs, high resolution, no signup. HDRIs are the cheapest large upgrade to
  how a 3D scene reads.
- **[ambientCG](https://ambientcg.com/)** — 2000+ CC0 PBR materials and HDRIs,
  with a plain albedo/roughness/normal folder layout that imports cleanly.

### Audio

- **[Kenney audio](https://kenney.nl/assets/category:Audio)** — all CC0.
  [Sci-fi Sounds](https://kenney.nl/assets/sci-fi-sounds) (70),
  [Impact Sounds](https://kenney.nl/assets/impact-sounds) (130),
  [Digital Audio](https://kenney.nl/assets/digital-audio) (60),
  [UI Audio](https://kenney.nl/assets/ui-audio) (50).

## Import pipeline: what actually happens

Godot 4.7 imports FBX **natively** — no FBX2glTF binary, no Blender round-trip.
Dropping the files into `assets/` and running `godot --headless --import` is
the whole process.

Three things cost real time on the first character, all of them recorded here
so nobody rediscovers them:

**Do not trust `get_aabb()` or bone rests to size a rigged model.** For a
skinned mesh, `MeshInstance3D.get_aabb()` returns pre-skinning bounds, and
`Skeleton3D.get_bone_global_rest()` lives in another space again. Both reported
the Kenney character as 0.037 units tall, implying a 48× scale. The real
rendered height is about 3.6 units, so the correct scale is **0.5** — a factor
of ~100 out. Measure by rendering the model beside a primitive of known size
and comparing; `tests/screenshot.gd` is the pattern to copy.

**The importer already applies axis correction.** Kenney's FBX files are
authored Z-up, but Godot lands them upright and Y-up. Adding a −90° X rotation
to "fix" it lays the character flat on its back.

**Animations arrive as separate FBX scenes.** Each clip file contains its own
`AnimationPlayer` and a duplicate skeleton. `Player._setup_animations()` lifts
the clips out and re-hosts them on one `AnimationPlayer` parented to the
character root, so the `Root/Skeleton3D:bone` track paths resolve against our
skeleton without rewriting. The clips also import non-looping, so `loop_mode`
is set explicitly.

## Adding an asset

1. Confirm the licence is CC0 and note it in the table above.
2. Drop the files under `assets/<category>/` with the pack's licence file.
3. `godot --headless --path . --import`
4. Size it against a known reference before trusting any measurement.
5. Re-render `docs/split-screen.png` and **look at it**.
