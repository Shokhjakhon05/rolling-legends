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

Current milestone: first playable build (0.1.0) for the owner to try on a phone.

Verified:
- [x] Godot project imports cleanly (CI)
- [x] Tests pass: rules, 30 levels each finished by a bot (CI)
- [x] Android debug APK, signed release APK and AAB export (CI run 38239049132)
- [ ] Real-device test (owner, Poco X6 Pro) - nobody has played it on a phone yet
- [ ] Ads seen on a device (test ids)

Not done: purchases, Rewind, music, endless and daily modes, worlds 4-6, store listing.

Next exact actions:
1. Owner plays the APK; tune scripts/core/balance.gd from the feedback.
2. Real AdMob ids into secrets ADMOB_APP_ID, REWARDED_AD_UNIT_ID, INTERSTITIAL_AD_UNIT_ID.
3. Privacy policy page, Play Console app, closed test.

Do not replace the engine mid-milestone. Do not add an online backend. Do not commit ad ids,
keystores or passwords.
