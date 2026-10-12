## A simple player used by the level validator: it looks a few metres ahead and steers for the
## lane that stays on the road and away from obstacles. If it can finish a level, a person can.
extends RefCounted

const B := preload("res://scripts/core/balance.gd")
const Track := preload("res://scripts/core/track.gd")

## Returns the steer value (-1..1) for this step. [greed] > 0 makes it go for crystals.
static func steer(sim: RefCounted, greed: float = 1.0) -> float:
	var t: RefCounted = sim.track
	var best_col: int = Track.col_of(sim.d)
	var best_score := -1e9
	for c in B.COLS:
		var dc: float = Track.d_of(c)
		var score: float = -absf(dc - sim.d) * 0.6
		# Road under this lane over the next stretch (holes that a jump clears do not count).
		var look := 11
		for k in range(1, look):
			var row := int(floor(sim.s)) + k
			if row >= t.rows:
				break
			if t.row_empty(row):
				continue
			var cell: int = t.cell(row, c)
			if cell != Track.Cell.SOLID or sim.fallen[row * B.COLS + c] == 1:
				score -= 30.0 / k
			else:
				# Prefer lanes with road on both sides.
				for side in [-1, 1]:
					if t.cell(row, c + side) != Track.Cell.SOLID:
						score -= 2.0 / k
		for b in t.barriers:
			var ahead: float = b["s0"] - sim.s
			if ahead > -1.0 and ahead < 12.0 and dc > b["d0"] - 0.62 and dc < b["d1"] + 0.62:
				score -= 60.0
		for p in t.pendulums:
			var ahead: float = p["s"] - sim.s
			if ahead > -1.0 and ahead < 10.0:
				var eta: float = maxf(ahead, 0.0) / maxf(sim.vs, 3.0)
				# The bob keeps moving while the ball passes it: look a moment either side.
				for shift in [-0.16, 0.0, 0.16]:
					var pd: float = Track.pendulum_d(p, sim.time + eta + shift)
					if absf(dc - pd) < p["r"] + 0.62:
						score -= 30.0
		for g in t.gates:
			var ahead: float = g["s"] - sim.s
			if ahead > -0.5 and ahead < 8.0:
				score -= absf(dc) * 6.0  # the opening is in the middle
		if greed > 0.0:
			for i in t.crystals.size():
				if sim.taken[i] == 1:
					continue
				var cr: Dictionary = t.crystals[i]
				var ahead: float = cr["s"] - sim.s
				if ahead > 0.0 and ahead < 9.0 and absf(cr["d"] - dc) < 0.6:
					score += greed * 8.0 / (1.0 + ahead * 0.2)
		if score > best_score:
			best_score = score
			best_col = c
	var want: float = Track.d_of(best_col) - sim.d
	# Lean against the bend before it pushes the ball out.
	want -= t.curvature_at(sim.s + 2.0) * sim.vs * sim.vs * 0.035
	return clampf(want * 1.6 - sim.vd * 0.12, -1.0, 1.0)

## Plays a whole level. Returns the finished run (state WON, or LOST after too many falls).
static func play(track: RefCounted, greed: float = 1.0, max_falls: int = 0, limit_s: float = 240.0) -> RefCounted:
	var Sim := load("res://scripts/core/sim.gd")
	var sim: RefCounted = Sim.new(track)
	var steps := int(limit_s / B.STEP)
	for i in steps:
		sim.step(steer(sim, greed))
		sim.events.clear()
		if sim.state == 3:  # WON
			break
		if sim.state == 2:  # LOST
			if sim.falls > max_falls:
				break
			sim.respawn()
	return sim
