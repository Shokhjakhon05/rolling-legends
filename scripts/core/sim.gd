## One run of a level: where the ball is and what happens to it. Advances in fixed steps from
## a single input (steer, -1..1), so the same inputs always give the same run - which is what
## lets a bot prove that every level can be finished.
extends RefCounted

const B := preload("res://scripts/core/balance.gd")
const Track := preload("res://scripts/core/track.gd")

enum State { RUNNING, FALLING, LOST, WON }

var track: RefCounted
var state := State.RUNNING
var time := 0.0            # level clock, runs only while the ball is in play
var s := 3.0
var d := 0.0
var h := 0.0
var vs := 0.0
var vd := 0.0
var vh := 0.0
var grounded := true
var boost_left := 0.0
var taken := PackedByteArray()      # per crystal: 1 = collected
var crystals := 0
var checkpoint := -1                # index of the last checkpoint reached
var falls := 0
var hits := 0
var _last_hit := -9.0
var _jump_wanted := 0.0             # seconds left in which a pressed jump may still happen
var _since_ground := 0.0
var jumps := 0
var fallen := PackedByteArray()     # per cell: 1 = dropped away
var behind_row := 0                 # rows before this one have collapsed
var events: Array[Dictionary] = []  # drained by whoever shows or tests the run

func _init(t: RefCounted) -> void:
	track = t
	taken.resize(track.crystals.size())
	fallen.resize(track.cells.size())

func progress() -> float:
	return clampf(s / maxf(track.finish_s, 1.0), 0.0, 1.0)

func solid(row: int, col: int) -> bool:
	if track.cell(row, col) == Track.Cell.NONE:
		return false
	return fallen[row * B.COLS + col] == 0

func solid_at(ps: float, pd: float) -> bool:
	return solid(int(floor(ps)), Track.col_of(pd))

## One fixed step. [steer] is -1..1; [jump] is true on the step the player presses jump.
func step(steer: float, jump: bool = false) -> void:
	if state == State.LOST:
		return
	if state == State.WON:
		_coast()
		return
	var dt := B.STEP
	steer = clampf(steer, -1.0, 1.0)
	if state == State.FALLING:
		vh -= B.GRAVITY * dt
		h += vh * dt
		s += vs * dt
		d += vd * dt
		if h < -B.FALL_DEPTH:
			state = State.LOST
			falls += 1
			events.append({"t": "lost"})
		return

	time += dt
	# Along the road: the ball always seeks its cruising speed; slopes and boosts shift it.
	var target: float = B.SPEED - sin(track.pitch_at(s)) * B.SLOPE_SPEED
	if boost_left > 0.0:
		boost_left -= dt
		target *= B.BOOST_FACTOR
	vs = move_toward(vs, target, B.SPEED_ACCEL * dt)
	# Across the road: the finger asks for a sideways speed, the ball gets there with inertia,
	# and a bend pushes it outwards.
	var control := 1.0 if grounded else 0.45
	vd = move_toward(vd, steer * B.SIDE_SPEED, B.SIDE_ACCEL * control * dt)
	if grounded:
		vd += track.curvature_at(s) * vs * vs * B.CENTRIFUGAL * dt

	s += vs * dt
	d += vd * dt

	# Jumping is the player's: a press is remembered for a moment so that one made just before
	# landing, or just after rolling off an edge, still counts.
	if jump:
		_jump_wanted = B.JUMP_BUFFER
	else:
		_jump_wanted = maxf(_jump_wanted - dt, 0.0)
	if grounded:
		_since_ground = 0.0
		if not solid_at(s, d):
			grounded = false
			vh = 0.0
	else:
		_since_ground += dt
	if _jump_wanted > 0.0 and vh <= 0.0 and h > -0.2 and (grounded or _since_ground <= B.COYOTE):
		grounded = false
		vh = B.JUMP_SPEED
		h = maxf(h, 0.0)
		_jump_wanted = 0.0
		_since_ground = 9.0
		jumps += 1
		events.append({"t": "launch"})
	if not grounded:
		var before := h
		vh -= B.GRAVITY * dt
		h += vh * dt
		if h <= 0.0 and vh <= 0.0:
			if before >= -B.LAND_TOLERANCE and solid_at(s, d):
				h = 0.0
				vh = 0.0
				grounded = true
				events.append({"t": "land"})
			elif h < -B.LAND_TOLERANCE:
				state = State.FALLING
				events.append({"t": "fall"})
				return

	_obstacles(dt)
	_pickups()
	_road_decay()
	if s >= track.finish_s and solid_at(s, d):
		state = State.WON
		events.append({"t": "win"})

func _obstacles(_dt: float) -> void:
	if h > B.TALL_HEIGHT:
		return
	var r := B.BALL_RADIUS
	if h <= B.BARRIER_HEIGHT:
		for b in track.barriers:
			_hit_box(b["s0"], b["s1"], b["d0"], b["d1"], r)
	for g in track.gates:
		var open: float = Track.gate_open(g, time)
		if open >= 0.999:
			continue
		# Two leaves slide apart from the middle; what is left of them blocks the road.
		var half := B.COLS * 0.5
		var gap := half * open
		_hit_box(g["s"] - 0.3, g["s"] + 0.3, -half, -gap, r)
		_hit_box(g["s"] - 0.3, g["s"] + 0.3, gap, half, r)
	for p in track.pendulums:
		var pd: float = Track.pendulum_d(p, time)
		var ds: float = s - p["s"]
		var dd: float = d - pd
		var reach: float = r + p["r"]
		var dist2 := ds * ds + dd * dd
		if dist2 < reach * reach:
			var dist := maxf(sqrt(dist2), 0.001)
			var push := reach - dist
			s += ds / dist * push
			d += dd / dist * push
			vd = Track.pendulum_vd(p, time) * 1.15 + dd / dist * 3.0
			vs *= 0.55 if ds < 0.0 else 1.0
			_hit()

func _hit_box(s0: float, s1: float, d0: float, d1: float, r: float) -> void:
	if d1 <= d0:
		return
	var cs := clampf(s, s0, s1)
	var cd := clampf(d, d0, d1)
	var ds := s - cs
	var dd := d - cd
	var dist2 := ds * ds + dd * dd
	if dist2 >= r * r:
		return
	if dist2 < 0.000001:
		# Centre inside the box: leave by the nearer face, the front one by preference.
		s = s0 - r
		vs = -absf(vs) * B.HIT_BOUNCE
		_hit()
		return
	var dist := sqrt(dist2)
	var push := r - dist
	s += ds / dist * push
	d += dd / dist * push
	if absf(ds) >= absf(dd):
		if ds < 0.0 and vs > 0.0:
			vs = -vs * B.HIT_BOUNCE
			_hit()
	else:
		if dd * vd < 0.0:
			vd = -vd * B.HIT_SIDE_BOUNCE

## After the finish line the ball rolls to a stop on the pad.
func _coast() -> void:
	var dt := B.STEP
	vs = move_toward(vs, 0.0, B.BRAKE * dt)
	vd = move_toward(vd, 0.0, B.BRAKE * dt)
	s = minf(s + vs * dt, float(track.rows) - 1.2)
	d += vd * dt
	if h > 0.0 or vh > 0.0:
		vh -= B.GRAVITY * dt
		h = maxf(h + vh * dt, 0.0)
		if h == 0.0:
			vh = 0.0

func _hit() -> void:
	# One knock is one hit, however many steps the bodies stay in touch.
	if time - _last_hit > 0.35:
		hits += 1
		events.append({"t": "hit"})
	_last_hit = time

func _pickups() -> void:
	for i in track.crystals.size():
		if taken[i] == 1:
			continue
		var c: Dictionary = track.crystals[i]
		var ds: float = s - c["s"]
		if ds < -B.PICKUP_RADIUS or ds > B.PICKUP_RADIUS:
			continue
		var dd: float = d - c["d"]
		var dh: float = h - c["h"]
		if ds * ds + dd * dd < B.PICKUP_RADIUS * B.PICKUP_RADIUS and absf(dh) < 1.4:
			taken[i] = 1
			crystals += 1
			events.append({"t": "crystal", "i": i})
	for i in track.checkpoints.size():
		if i > checkpoint and s >= track.checkpoints[i]:
			checkpoint = i
			events.append({"t": "checkpoint", "i": i})
	if grounded and boost_left < B.BOOST_TIME - 0.5:
		for b in track.boosts:
			if s >= b["s0"] and s <= b["s1"] and d >= b["d0"] and d <= b["d1"]:
				boost_left = B.BOOST_TIME
				events.append({"t": "boost"})

func _road_decay() -> void:
	# Cracked tiles ahead drop before the ball gets to them: a hole the player sees coming.
	var ahead := int(floor(s + B.CRUMBLE_FALL))
	for r in range(maxi(int(floor(s)), 0), mini(ahead + 1, track.rows)):
		for c in B.COLS:
			var i := r * B.COLS + c
			if track.cells[i] == Track.Cell.CRUMBLE and fallen[i] == 0:
				fallen[i] = 1
				events.append({"t": "crumble", "row": r, "col": c})
	# The road behind falls away. It never matters to a ball rolling on - it is the pressure.
	var gone := int(floor(s - B.COLLAPSE_BEHIND))
	while behind_row < gone and behind_row < track.rows:
		for c in B.COLS:
			fallen[behind_row * B.COLS + c] = 1
		events.append({"t": "collapse", "row": behind_row})
		behind_row += 1

## Back into play after a fall: at the last checkpoint, or at the start. The clock keeps
## running; collected crystals stay collected.
func respawn() -> void:
	var at := 3.0
	if checkpoint >= 0:
		at = track.checkpoints[checkpoint]
	s = at
	d = 0.0
	h = 0.0
	vs = 0.0
	vd = 0.0
	vh = 0.0
	grounded = true
	boost_left = 0.0
	state = State.RUNNING
	behind_row = maxi(int(at) - 4, 0)
	for i in range(behind_row * B.COLS, fallen.size()):
		fallen[i] = 0
	events.append({"t": "respawn"})

func stars() -> int:
	if state != State.WON:
		return 0
	var n := 1
	if crystals >= track.star_crystals:
		n += 1
		if falls == 0 and (track.par_time <= 0.0 or time <= track.par_time):
			n += 1
	return n
