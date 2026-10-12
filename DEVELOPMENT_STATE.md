# DEVELOPMENT_STATE.md

Project: Rolling Legends - Android 3D rolling-ball arcade. Spec: the owner's "Project Bible"
(PDF, 2026-10-12); what was changed from it and why is in docs/GAME_DESIGN.md.

Locked decisions:
- Engine: Godot 4.6.3 (GL Compatibility renderer); exact version in .github/workflows/build.yml.
- No editor in the workflow: scenes are built in code, levels are JSON written by
  tool/gen_levels.py. The owner's laptop cannot build; everything heavy runs in GitHub Actions.
- The run is a deterministic simulation in road coordinates (scripts/core/sim.gd), not a
  physics body. This is what lets tests/run_tests.gd prove every level with a bot.
- Ads only through scripts/services/ads_service.gd; real ad ids only in repository secrets.
- AdMob plugin (Poing Studios v5.1.0) is fetched by tool/fetch_admob.sh, never committed.

Current milestone: 0.2.0 - answers the owner's first session on a phone (2026-10-12).

What 0.2.0 changed:
- Jumping is the player's (buttons in both bottom corners, a second finger, or a quick tap);
  a press is buffered 0.14 s and forgiven 0.1 s after an edge. Gaps are lost without a jump.
- Steering: the ball follows the finger (drag maps to a position across the road), instead of
  a joystick with inertia. Numbers in scripts/core/balance.gd.
- After the finish line the ball brakes to a stop on the pad; no input is taken.
- Look: stone slab texture and raised border stones, sun shadows, restrained glow, faceted
  islands with trees and clouds, banded mesas, lit towers, supports under the road.
- Balls are small models (scripts/game/skins.gd build()): Solar Gold, Neon Reactor,
  Obsidian Core have their own rings, studs, shell and core.
- A music loop per world (synthesised), pickup and landing effects.
- CI: `-f ads=test|real` decides which ad ids a build carries; test is the default.

Verified:
- [x] Tests pass: rules, jump, gap failure, finish stop, rewards paid once, 30 levels by a bot
- [x] Android release APK/AAB export and signing (CI)
- [x] 0.1.0 launched and was played by the owner on a phone (two screen recordings)
- [ ] 0.2.0 on a phone: look, steering feel, jump timing, music - not yet seen by anyone
- [ ] An ad actually shown on a device (test or real) - never observed
- [ ] Frame rate on a phone - never measured; the emulator cannot draw the 3D scene at all
      (its software GL has too few fragment uniforms), so CI only proves start-up and scripts

Not done: purchases, Rewind, endless and daily modes, worlds 4-6, store listing, waterfalls and
other set pieces from the concept art, a low-cost graphics preset.

Next exact actions:
1. Owner plays 0.2.0 (test ads) and reports; tune balance.gd and the look from that.
2. Build with `-f ads=real` for the store only after the owner accepts a build.
3. Privacy policy page, Play Console app, closed test.

Do not replace the engine mid-milestone. Do not add an online backend. Do not commit ad ids,
keystores or passwords.
