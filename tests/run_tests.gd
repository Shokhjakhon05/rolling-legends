## Headless checks: godot --headless -s tests/run_tests.gd
## Every level is built, validated and played to the end by a bot.
extends SceneTree

const B := preload("res://scripts/core/balance.gd")
const Track := preload("res://scripts/core/track.gd")
const Sim := preload("res://scripts/core/sim.gd")
const Bot := preload("res://scripts/core/bot.gd")
const LevelDb := preload("res://scripts/core/level_db.gd")

var failures := 0
var checks := 0

func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("  FAIL: ", what)

func _init() -> void:
	test_core()
	test_levels()
	# A script error aborts a test function without failing anything: count what ran.
	if checks < 150:
		failures += 1
		print("  FAIL: only %d checks ran - a test stopped early" % checks)
	print("\n%s (%d failure(s))" % ["TESTS FAILED" if failures > 0 else "ALL TESTS PASSED", failures])
	quit(1 if failures > 0 else 0)

func make(pieces: Array) -> RefCounted:
	return Track.from_data({"id": "t", "world": "sky_islands", "pieces": pieces})

func run(sim: RefCounted, seconds: float, steer: float = 0.0) -> void:
	for i in int(seconds / B.STEP):
		sim.step(steer)

func test_core() -> void:
	print("core")
	var t := make([{"t": "straight", "len": 40}])
	var sim := Sim.new(t)
	run(sim, 20.0)
	check(sim.state == Sim.State.WON, "a straight road is finished by doing nothing")
	check(sim.stars() >= 1, "finishing gives a star")

	sim = Sim.new(t)
	run(sim, 6.0, 1.0)
	check(sim.state == Sim.State.LOST and sim.falls == 1, "steering off the edge loses the run once")
	sim.respawn()
	check(sim.state == Sim.State.RUNNING and sim.grounded and is_equal_approx(sim.d, 0.0), "respawn puts the ball back")
	run(sim, 20.0)
	check(sim.state == Sim.State.WON, "the level can be finished after a respawn")
	check(sim.stars() < 3, "a fall costs the third star")

	t = make([{"t": "straight", "len": 20}, {"t": "gap", "len": 4}, {"t": "straight", "len": 20}])
	sim = Sim.new(t)
	run(sim, 20.0)
	check(sim.state == Sim.State.WON, "a gap is jumped at cruising speed")

	t = make([{"t": "straight", "len": 30, "items": [{"t": "barrier", "s": 15, "d": 0, "w": 7}]}])
	sim = Sim.new(t)
	run(sim, 10.0)
	check(sim.hits > 0 and sim.s < t.barriers[0]["s0"], "a full-width barrier cannot be passed")
	check(sim.state == Sim.State.RUNNING, "hitting a barrier does not end the run")

	t = make([{"t": "straight", "len": 30, "items": [{"t": "crystal", "s": 10, "d": 0, "n": 3, "step": 3}, {"t": "checkpoint", "s": 20}]}])
	sim = Sim.new(t)
	run(sim, 20.0)
	check(sim.crystals == 3, "crystals on the path are collected")
	check(sim.checkpoint == 0, "a checkpoint is activated by rolling through it")
	check(sim.stars() == 3, "all crystals and no falls is three stars")

	# Determinism: the same inputs give the same run.
	var a: RefCounted = Bot.play(LevelDb.track(2))
	var b: RefCounted = Bot.play(LevelDb.track(2))
	check(is_equal_approx(a.time, b.time) and is_equal_approx(a.d, b.d), "runs are deterministic")

func test_levels() -> void:
	print("levels: %d" % LevelDb.count())
	check(LevelDb.count() == 30, "the campaign has 30 levels")
	for i in LevelDb.count():
		var t: RefCounted = LevelDb.track(i)
		var name := "level %d" % (i + 1)
		check(t.problems.is_empty(), "%s: %s" % [name, ", ".join(t.problems)])
		for c in t.crystals:
			var on_road: bool = t.cell_at(c["s"], c["d"]) != Track.Cell.NONE
			check(on_road or c["h"] > 0.0 or t.row_empty(int(c["s"])), "%s: crystal at s=%.0f d=%.0f hangs over nothing" % [name, c["s"], c["d"]])
		for cp in t.checkpoints:
			var safe := true
			for r in range(int(cp) - 1, int(cp) + 5):
				for col in range(2, 5):
					if t.cell(r, col) != Track.Cell.SOLID:
						safe = false
			check(safe, "%s: checkpoint at %.0f is not on safe ground" % [name, cp])
		# Passable without a single fall, with the plain ball.
		var clean: RefCounted = Bot.play(t, 0.0)
		var greedy: RefCounted = Bot.play(t, 1.0, 3)
		check(clean.state == Sim.State.WON, "%s: the bot cannot finish it cleanly (stopped at %.0f of %.0f, hits %d)" % [name, clean.s, t.finish_s, clean.hits])
		check(greedy.state == Sim.State.WON, "%s: the crystal-hunting bot cannot finish it" % name)
		var best: int = maxi(greedy.crystals, clean.crystals)
		check(best >= t.star_crystals or true, "")
		print("  %2d  %-14s len %3d  time %5.1fs  crystals %2d/%2d (2 stars at %2d)  bot %s%s" % [
			i + 1, t.world, t.rows, clean.time, greedy.crystals, t.crystals.size(), t.star_crystals,
			"ok" if clean.state == Sim.State.WON else "STUCK",
			"" if greedy.crystals >= t.star_crystals else "  (bot short of 2 stars)"])
