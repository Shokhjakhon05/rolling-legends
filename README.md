# Rolling Legends

A 3D rolling-ball arcade game for Android, made with Godot 4.6.

- `scripts/core/` - the rules: track building, the run simulation, the validator bot. No nodes.
- `scripts/game/` - drawing a level and playing it. `scripts/services/` - saves, texts, sound, ads.
- `data/levels/` - the 30 campaign levels (generated: edit `tool/gen_levels.py`).
- `tests/run_tests.gd` - `godot --headless -s tests/run_tests.gd`.

Builds are made in GitHub Actions (`build.yml`); `smoke.yml` runs a built APK on an emulator.
State of the project: `DEVELOPMENT_STATE.md`.
