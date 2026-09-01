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

| Asset | Source | Licence | Used for |
| --- | --- | --- | --- |
| `assets/materials/MetalPlates008/` | [ambientCG](https://ambientcg.com/view?id=MetalPlates008) | CC0 | Floor |
| `assets/materials/MetalPlates006/` | [ambientCG](https://ambientcg.com/view?id=MetalPlates006) | CC0 | Cover blocks |
| `assets/materials/Concrete034/` | [ambientCG](https://ambientcg.com/view?id=Concrete034) | CC0 | Boundary walls |

The 1K-JPG variants, keeping only Color, NormalGL, Roughness and Metalness.
Displacement is deliberately dropped: parallax is a per-pixel cost, and split
screen pays it four times.

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

**Materials use world-space triplanar mapping.** Godot's `BoxMesh` lays its
six faces out across the UV square, so a tiling texture on a 48-metre floor
box would smear. `uv1_triplanar` with `uv1_world_triplanar` projects the
texture in world space instead: no UV authoring, and the same tile size on
every box whatever its dimensions. `uv1_scale` is the reciprocal of the tile
size in metres.

**A fill light must have zero specular.** The first textured render had a
blinding white streak across the floor in one player's view and nowhere
else. It was not bloom, not metalness and not the sky's sun disc — each was
ruled out in turn, and the streak did not change. Rendering with each light
disabled showed it came from the cool fill light: at a low angle, even
`light_specular = 0.2` produces a huge grazing highlight on a glossy floor for
whichever camera happens to sit at the mirror angle. A fill exists to soften
shadows, so its specular is now 0. (The key light also has
`sky_mode = SKY_MODE_LIGHT_ONLY`, kept from the sun-disc theory: it is
harmless and stops the sky ever painting a disc for the floor to reflect.)

**ambientCG's zips include a `.tres`.** It is a usable Godot material as-is,
but it enables the heightmap and uses plain UVs, so this project writes its
own material and only borrows the texture-channel settings from it.

**Animations arrive as separate FBX scenes.** Each clip file contains its own
`AnimationPlayer` and a duplicate skeleton. `Player._setup_animations()` lifts
the clips out and re-hosts them on one `AnimationPlayer` parented to the
character root, so the `Root/Skeleton3D:bone` track paths resolve against our
skeleton without rewriting. The clips also import non-looping, so `loop_mode`
is set explicitly.

## What the headless render can and cannot show

`tests/screenshot.gd` renders through Forward+ using software Vulkan
(lavapipe), which is what makes a screenshot possible on a machine with no GPU:

```bash
apt-get install -y mesa-vulkan-drivers vulkan-tools xvfb
VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json \
    xvfb-run godot --path . --script res://tests/screenshot.gd
```

**Software Vulkan does not rasterise directional shadows.** This was confirmed
with a minimal scene — a single box on a plane under a shadow-casting
directional light produces no shadow at all. Everything else checked out:
sky, AgX tonemapping, glow, depth fog and SSAO all render correctly, SSAO
verified by toggling it and seeing contact darkening appear.

So the committed screenshot **understates** the real look, and shadow settings
— cascade splits, bias, blur, sun angle — are the one part of the lighting that
has never been seen. They need a pass on real hardware.

## Adding an asset

1. Confirm the licence is CC0 and note it in the table above.
2. Drop the files under `assets/<category>/` with the pack's licence file.
3. `godot --headless --path . --import`
4. Size it against a known reference before trusting any measurement.
5. Re-render `docs/split-screen.png` and **look at it**.
