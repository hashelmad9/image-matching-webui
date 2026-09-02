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

## M2b — The hub and the modes ✅

The game is now a rotating collection of short rounds rather than one
deathmatch. Each mode is a small rules class; see DESIGN.md.

- [x] Round flow: lobby with mode select → countdown → play → results →
      next mode, with a session-wins scoreboard
- [x] **Horde** (co-op): waves, zombie AI, downed state, proximity revive
- [x] **Deathmatch**, **Tag**, **King of the Hill**, **Ball Game** (2v2)
- [x] Friendly fire off in co-op; shots pass through teammates
- [x] Per-player HUD: health bar, mode status, event toasts, state banner
- [x] Lobby panel with seats and mode carousel; countdown; results panel with
      standings and the mutator ballot
- [x] Every mode announces its moments: kill feed, bounty, tag hand-offs,
      hill changes, goals, wave calls, down and revive

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

- [x] Muzzle flash and a tracer that reads at distance
- [x] Hit feedback: victim flash, impact spark, a hit marker for the shooter
- [x] Death: the body falls and lies there before the respawn, rather than
      vanishing (a proper animation or ragdoll is still open)
- [x] Respawn: materialise pop and a spawn-protection blink
- [x] Screen shake on firing and on taking damage, per viewport
- [ ] Aim/shoot animations — the Kenney pack has only idle/run/jump, so this
      likely means pulling clips from [KayKit](https://kaylousberg.itch.io/kaykit-character-animations)
- [x] Camera collision. Note: at the current camera height nothing in this
      arena is tall enough to trigger it; it exists for taller geometry

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
- [x] Replace box cover with modelled props — the Modular Space Kit
- [x] PBR floor, wall and cover materials from [ambientCG](https://ambientcg.com/),
      triplanar-mapped so nothing needed UVs
- [x] HDRI sky (Poly Haven sunset) in place of the procedural one
- [ ] **Bake lighting** with LightmapGI — the arena is static and drawn four
      times, so baked light is both cheaper and better than realtime here
- [ ] Re-measure framerate after each addition, not at the end

---

## M6 — A match, not a sandbox

- [x] Score limit or time limit, and a round that actually ends
- [x] Countdown before a round starts
- [x] Between-round screen with final scores
- [x] Spawn protection so camping is not free
- [x] Bounty on the leader in deathmatch: killing whoever is ahead is worth two
- [x] Mutator vote between rounds: one-hit kills, infinite ricochet, fast
      feet, rapid fire, glass cannon — three on each ballot, X/Y/B to vote
- [x] Ricochet as a signature mechanic: every shot bounces off cover once
- [x] Sudden death on a tie: the versus modes play on until the next point

---

## M7 — Content and variety

- [x] A second and third weapon with meaningfully different feel: a scatter
      gun and a rail gun, Kenney Blaster Kit models in hand
- [x] Weapon pickups at the four mid-edges, respawning after a delay
- [x] Two arenas built from Kenney's Modular Space Kit, chosen in Match Setup
- [x] Team mode (2v2) — the ball game
- [x] Pathfinding for horde enemies: a navigation mesh baked at startup
- [x] Horde variety: runners from wave 2, brutes from wave 4
- [x] A boss every fifth wave

---

## M8 — Audio

Sound is the cheapest large gain in perceived quality and is routinely left
too late. All of this is CC0 and already located — see [ASSETS.md](ASSETS.md).

- [x] Weapon fire, impacts, death, respawn, pickups, waves, goals, tags
- [x] UI: countdown ticks, round start, results bell, votes
- [ ] Footsteps
- [ ] Music, with a duck under gunfire
- [ ] Positional audio — deliberately not attempted: four cameras means four
      listeners and one pair of speakers. Everything is non-positional for now

---

## M7b — Left open on purpose

- [ ] Weapon models sit at a fixed offset from the player, not in a hand bone.
      The Kenney rig's skin carries a large bind scale, so a BoneAttachment3D
      needs calibrating by render like the character did
- [ ] Baked lighting (LightmapGI). Needs UV2 on every mesh and a lightmapper
      run; the primitives here have no UV2. Worth it once the arena is final

## M9 — Shipping

- [x] Main menu, pause, options (volume, camera, invert aim, deadzone, shake,
      hit flash, window mode, v-sync) and match setup — all pad-navigable,
      persisted to `user://settings.cfg`
- [ ] Windows export, tested on a machine that is not the dev machine
- [ ] Icon and window branding
- [ ] Choose a licence
- [ ] Controller compatibility pass on hardware you do not own, if you can

---

## What I would do next, in order

Everything above that is unticked falls into two piles.

**Needs a person and a machine** — nothing here can be done from a container:

1. Play it with two controllers (M3). Every number in the game is a guess
   until this happens. Watch the camera, the hit flash, wave-one pacing,
   scatter range, and whether ricochet reads as skill or chaos.
2. Look at the shadows (M3/M5). Never rendered by software Vulkan.
3. Measure the four-way split's framerate with SSAO and glow on (M3).
4. Windows export on a second machine (M9).

**Can be built headlessly** — pick any:

5. A third arena from the kit's corridor and room pieces: interior lanes and
   rooms rather than open ground with cover, and stairs for the first
   verticality. A genuinely different fight, and the first thing that would
   make camera collision earn its keep.
6. A minimap, now that the camera is close. Split screen hides nothing, so a
   shared minimap costs nothing — and enemies now arrive from off-screen.
7. Shoulder offset for the camera, so the player's own body is in frame.
8. Aim and shoot animations from KayKit's animation pack (M4). The one visual
   gap left that is asset-gated rather than skill-gated.
9. Footsteps and music with a duck under gunfire (M8). Music needs a CC0
   source; Kenney's "Music Jingles" covers stings but not a loop.
10. Sudden-death variants — walls closing in, one shared weapon — and a
    kill-cam or replay of the winning shot on the results screen.
11. Weapon models in a hand bone rather than a fixed offset (M7b).
12. Baked lighting (M7b), once the arenas are final.

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
