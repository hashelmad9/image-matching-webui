# Roadmap

The path from working prototype to a game that looks and feels good. Each
milestone is scoped to be finishable in roughly one sitting and to leave the
game playable at the end of it — never half-refactored.

Before starting a milestone, read [../CLAUDE.md](../CLAUDE.md). For where art
comes from and how to import it, read [ASSETS.md](ASSETS.md).

---

## The two things that decide whether this looks good

**Coherence beats fidelity.** The fastest way to make this look cheap is to mix
CC0 packs from different artists — a realistic PBR wall next to a flat-shaded
character reads as broken, however good each piece is on its own. Pick one
stylised look and hold it. Kenney and Quaternius both work; mixing them
carelessly does not. A consistent simple style will beat an inconsistent
expensive one every time, and it is far cheaper to reach.

**Split screen multiplies every rendering cost by four.** The scene is drawn
once per player. An effect that costs 4ms full-screen costs 16ms at four
players and blows the frame budget on its own. This single fact should govern
every rendering decision below, and it is why the expensive-looking options
(SDFGI, screen-space reflections, depth of field) are deliberately not on this
list. Baked lighting and cheap post-processing are the right tools here.

---

## M1 — Technical core ✅

- [x] Split-screen viewports that re-tile as players join and leave
- [x] Drop-in / drop-out joining on any gamepad, plus a keyboard seat
- [x] Twin-stick movement and aiming with a third-person follow camera
- [x] Arena with boundary walls and cover
- [x] Projectiles, hit detection, health, death, respawn, kill scoring
- [x] Per-player HUD and lobby prompt
- [x] Headless test suite and a headless render check

---

## M2 — Real characters ✅

- [x] Replace capsules with a rigged, animated character
- [x] A distinct skin per player seat
- [x] Idle and run animations driven by movement
- [x] Camera reframed (narrower FOV) so characters read at split-screen size

**Not done:** never played on real hardware. Everything below is informed
guesswork until that happens.

---

## M3 — Play it, then fix what is wrong

Nothing further is worth building until a human has held a controller. This
milestone is deliberately first among the remaining work.

- [ ] **Play it with real controllers and write down what feels wrong.**
- [ ] Verify Xbox, PlayStation and generic pads all map correctly
- [ ] Tune speed, turn rate, camera distance and fire rate against that feedback
- [ ] Confirm four-way split holds a stable framerate on the target machine —
      measure before optimising, and record the number
- [ ] **Look at the shadows.** They have never been seen: software Vulkan does
      not draw them, so cascade splits, bias, blur and sun angle are all set
      blind. Expect to adjust them.
- [ ] Decide whether SSAO and glow survive the four-viewport budget

---

## M4 — Game feel

This is the milestone that makes the difference between "works" and "good". It
is worth more than any amount of extra art.

- [ ] Muzzle flash and a tracer that reads at distance
- [ ] Hit feedback: victim flash, impact spark, a hit marker for the shooter
- [ ] Death: ragdoll or a death animation, not the body silently vanishing
- [ ] Respawn: a brief materialise effect and invulnerability window
- [ ] Screen shake on firing and on taking damage, scaled per viewport
- [ ] Aim/shoot animations — the Kenney pack has only idle/run/jump, so this
      likely means pulling clips from [KayKit](https://kaylousberg.itch.io/kaykit-character-animations)
- [ ] Camera collision, so cover cannot sit between camera and player

---

## M5 — Environment and lighting

Where the arena stops looking like grey boxes. The lighting half is done; the
material half is not.

- [x] Sky-based ambient replacing the flat colour wash, which also fills the
      dead black space above the walls
- [x] Warm key light with shadow cascades, plus a cool unshadowed fill
- [x] AgX tonemapping
- [x] Glow, with emissive tracers bright enough to actually bloom
- [x] SSAO and depth fog
- [ ] **Verify the shadows on real hardware** — see M3; they are set blind
- [ ] Commit to one art direction in writing, then judge every asset against it
- [ ] Replace box cover with modelled props ([Kenney Prototype Kit](https://kenney.nl/assets/prototype-kit),
      [Quaternius Sci-Fi Essentials](https://quaternius.com/packs/scifiessentialskit.html))
- [ ] PBR floor and wall materials from [ambientCG](https://ambientcg.com/) or
      [Poly Haven](https://polyhaven.com/textures) — the floor is a large flat
      expanse and is now the weakest thing on screen
- [ ] Consider an HDRI sky in place of the procedural one
- [ ] **Bake lighting** with LightmapGI — the arena is static and drawn four
      times, so baked light is both cheaper and better than realtime here
- [ ] Re-measure framerate after each addition, not at the end

---

## M6 — A match, not a sandbox

- [ ] Score limit or time limit, and a round that actually ends
- [ ] Countdown before a round starts
- [ ] Between-round screen with final scores
- [ ] Spawn protection so camping is not free

---

## M7 — Content and variety

- [ ] A second and third weapon with meaningfully different feel
      ([Kenney Blaster Kit](https://kenney.nl/assets/blaster-kit) covers the models)
- [ ] Weapon pickups spawning around the arena
- [ ] A second arena, and a way to choose between them
- [ ] Team mode (2v2) as an alternative to free-for-all

---

## M8 — Audio

Sound is the cheapest large gain in perceived quality and is routinely left
too late. All of this is CC0 and already located — see [ASSETS.md](ASSETS.md).

- [ ] Weapon fire, impacts, footsteps, death, respawn
- [ ] UI and countdown sounds
- [ ] Music, with a duck under gunfire
- [ ] Positional audio, and check what that means with four listeners — Godot
      has one audio listener per viewport, which needs explicit handling

---

## M9 — Shipping

- [ ] Main menu, pause, and a settings screen (volume, invert aim, window mode)
- [ ] Windows export, tested on a machine that is not the dev machine
- [ ] Icon and window branding
- [ ] Choose a licence
- [ ] Controller compatibility pass on hardware you do not own, if you can

---

## Quality bar

A milestone is done when all of these hold:

- `godot --headless --path . --script res://tests/run_tests.gd` passes
- `docs/split-screen.png` has been re-rendered and **looked at**
- Four-way split still holds its framerate target on real hardware
- No asset in the tree has an unrecorded licence

---

## Deliberately out of scope

**Online multiplayer.** This is a couch game. Netcode would cost more than
every milestone above combined and would change the design of all of them.

**Photorealism.** Four viewports and a small team make this a losing race.
A confident stylised look is both achievable and ages better.

**Custom character art.** Commissioning or modelling characters is months of
work. The CC0 packs are good enough to ship with; revisit only if the game is
succeeding and the art is the thing holding it back.
