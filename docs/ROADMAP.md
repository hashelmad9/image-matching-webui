# Roadmap

This project is built across many short sessions. Each milestone is scoped to
be finishable in roughly one sitting and to leave the game playable at the end
of it — never half-refactored.

Before starting a milestone, read [../CLAUDE.md](../CLAUDE.md).

---

## M1 — Technical core ✅

Four gamepads, four viewports, capsules that move, aim, shoot, die and respawn.

- [x] Split-screen viewports that re-tile as players join and leave
- [x] Drop-in / drop-out joining on any gamepad, plus a keyboard seat
- [x] Twin-stick movement and aiming with a third-person follow camera
- [x] Arena with boundary walls and cover
- [x] Projectiles, hit detection, health, death, respawn, kill scoring
- [x] Per-player HUD and lobby prompt
- [x] Headless test suite and a headless render check

**Not done:** never played on real hardware. That is the first job of M2.

---

## M2 — Make it feel good

The gap between "works" and "fun" lives entirely in this milestone. Nothing
below is worth doing until a human has played M1 and reported back.

- [ ] **Play it and write down what feels wrong.** Everything else here is a
      guess until this happens.
- [ ] Verify real controllers map correctly — Xbox, PlayStation, generic pads
- [ ] Tune speed, turn rate, camera distance and fire rate against that feedback
- [ ] Hit feedback: flash the victim, a muzzle flash, a hit marker
- [ ] Death and respawn feedback rather than the capsule silently vanishing
- [ ] Camera collision, so cover cannot sit between the camera and the player

---

## M3 — A match, not a sandbox

- [ ] Score limit or time limit, and a round that actually ends
- [ ] Between-round screen with final scores
- [ ] Countdown before a round starts
- [ ] Respawn invulnerability, so spawn camping is not free

---

## M4 — Content

- [ ] A second and third weapon with meaningfully different feel
- [ ] Weapon pickups spawning around the arena
- [ ] A second arena, and a way to choose between them
- [ ] Team mode (2v2) as an alternative to free-for-all

---

## M5 — Presentation

- [ ] Replace capsules with actual character models and animation
- [ ] Sound: firing, impacts, footsteps, music
- [ ] Main menu and pause
- [ ] Settings: volume, invert aim, window mode

---

## M6 — Shipping

- [ ] Windows export, tested on a machine that is not the dev machine
- [ ] Icon and window branding
- [ ] Choose a licence

---

## Deliberately out of scope

**Online multiplayer.** This is a couch game. Netcode would cost more than
every milestone above combined and would change the design of all of them.

**A level editor.** Arenas are small and built in the Godot editor already,
which is the level editor.
