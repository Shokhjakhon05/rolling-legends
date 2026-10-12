## A level's road, built from its data: a grid of cells laid along a path, plus the things
## standing on it. Pure data and maths - no nodes - so levels can be checked without a screen.
extends RefCounted

const B := preload("res://scripts/core/balance.gd")

enum Cell { NONE, SOLID, CRUMBLE }

var id := ""
var world := ""
var rows := 0
var cells := PackedByteArray()          # rows * COLS
var pos := PackedVector3Array()         # centre of each row
var yaw := PackedFloat32Array()         # heading of each row, radians, + = left
var pitch := PackedFloat32Array()       # slope of each row, radians, + = uphill
var curvature := PackedFloat32Array()   # d(yaw)/ds
var launch := PackedFloat32Array()      # > 0 on the last row before a gap: the take-off strip
var crystals: Array[Dictionary] = []    # {s, d, h}
var checkpoints: PackedFloat32Array = []
var barriers: Array[Dictionary] = []    # {s0, s1, d0, d1}
var pendulums: Array[Dictionary] = []   # {s, amp, period, phase, r}
var gates: Array[Dictionary] = []       # {s, period, open, phase}
var boosts: Array[Dictionary] = []      # {s0, s1, d0, d1}
var finish_s := 0.0
var star_crystals := 0
var par_time := 0.0
var problems: PackedStringArray = []

static func from_data(data: Dictionary) -> RefCounted:
	var t = new()
	t._build(data)
	return t

func length() -> float:
	return float(rows)

func cell(row: int, col: int) -> int:
	if row < 0 or row >= rows or col < 0 or col >= B.COLS:
		return Cell.NONE
	return cells[row * B.COLS + col]

static func col_of(d: float) -> int:
	return int(floor(d / B.CELL + B.COLS * 0.5))

static func d_of(col: int) -> float:
	return (col - (B.COLS - 1) * 0.5) * B.CELL

func cell_at(s: float, d: float) -> int:
	return cell(int(floor(s)), col_of(d))

func curvature_at(s: float) -> float:
	return curvature[clampi(int(s), 0, rows - 1)] if rows > 0 else 0.0

func pitch_at(s: float) -> float:
	return pitch[clampi(int(s), 0, rows - 1)] if rows > 0 else 0.0

## World position of a point given in road coordinates: along, across (+ = right), above.
func to_world(s: float, d: float, h: float) -> Vector3:
	var f := clampf(s, 0.0, float(rows) - 0.001)
	var i := int(f)
	var k := f - i
	var j := mini(i + 1, rows - 1)
	var y := lerp_angle(yaw[i], yaw[j], k)
	var p := pos[i] + forward(yaw[i], pitch[i]) * k
	if j != i and i + 1 < rows:
		p = pos[i].lerp(pos[j], k)
	return p + right(y) * d + Vector3.UP * h

func yaw_at(s: float) -> float:
	var f := clampf(s, 0.0, float(rows) - 0.001)
	var i := int(f)
	return lerp_angle(yaw[i], yaw[mini(i + 1, rows - 1)], f - i)

static func forward(y: float, p: float = 0.0) -> Vector3:
	return Vector3(-sin(y) * cos(p), sin(p), -cos(y) * cos(p))

static func right(y: float) -> Vector3:
	return Vector3(cos(y), 0.0, -sin(y))

# --- Building -----------------------------------------------------------------------------

var _cursor := Vector3.ZERO
var _yaw := 0.0

func _build(data: Dictionary) -> void:
	id = str(data.get("id", ""))
	world = str(data.get("world", "sky_islands"))
	var stars: Dictionary = data.get("stars", {})
	par_time = float(stars.get("par", 0))
	var pieces: Array = data.get("pieces", [])
	if pieces.is_empty():
		problems.append("no pieces")
	_add_rows(6, B.COLS, 0.0, 0.0)  # start pad
	for piece in pieces:
		_add_piece(piece)
	finish_s = float(rows) + 2.0
	_add_rows(B.FINISH_PAD, B.COLS, 0.0, 0.0)
	star_crystals = int(stars.get("crystals", crystals.size()))
	_set_launches()

func _add_piece(p: Dictionary) -> void:
	var kind := str(p.get("t", "straight"))
	var start := rows
	var width := int(p.get("width", B.DEFAULT_WIDTH))
	var n := int(p.get("len", 10))
	var rise := float(p.get("rise", 0.0))
	match kind:
		"straight", "hole", "crumble":
			_add_rows(n, width, 0.0, rise)
		"turn":
			var angle := deg_to_rad(float(p.get("angle", 45.0)))
			_add_rows(n, width, angle / maxf(n, 1), rise)
		"gap":
			_add_rows(n, 0, 0.0, rise)
		"islands":
			var plat := int(p.get("plat", 5))
			var gap := int(p.get("gap", 3))
			for i in int(p.get("count", 3)):
				_add_rows(gap, 0, 0.0, 0.0)
				_add_rows(plat, width, 0.0, 0.0)
			n = rows - start
		_:
			problems.append("unknown piece '%s'" % kind)
			return
	if kind == "hole":
		# Columns "from".."to" (0 = leftmost of the 7) are missing over rows "at".."at+rows".
		var a := int(p.get("at", 0))
		var m := int(p.get("rows", n - a))
		for r in range(start + a, mini(start + a + m, rows)):
			for c in range(int(p.get("from", 0)), int(p.get("to", 0)) + 1):
				_set_cell(r, c, Cell.NONE)
	if kind == "crumble":
		# "cols": the cracked columns; "rows"/"at" as above; "alt": the pattern flips every N rows.
		var a := int(p.get("at", 2))
		var m := int(p.get("rows", n - a - 2))
		var cols: Array = p.get("cols", [1, 2])
		var alt := int(p.get("alt", 0))
		for k in m:
			var r := start + a + k
			var flip := alt > 0 and (k / alt) % 2 == 1
			for c in cols:
				var col := int(c)
				if flip:
					col = B.COLS - 1 - col
				if cell(r, col) == Cell.SOLID:
					_set_cell(r, col, Cell.CRUMBLE)
	for item in p.get("items", []):
		_add_item(item, start, n)

func _add_rows(n: int, width: int, dyaw: float, rise: float) -> void:
	var p := atan2(rise, maxf(n, 1)) if rise != 0.0 else 0.0
	var first := (B.COLS - width) / 2
	for i in n:
		_yaw += dyaw
		pos.append(_cursor)
		yaw.append(_yaw)
		pitch.append(p)
		curvature.append(dyaw)
		launch.append(0.0)
		for c in B.COLS:
			cells.append(Cell.SOLID if width > 0 and c >= first and c < first + width else Cell.NONE)
		_cursor += forward(_yaw, p)
		rows += 1

func _set_cell(r: int, c: int, v: int) -> void:
	if r >= 0 and r < rows and c >= 0 and c < B.COLS:
		cells[r * B.COLS + c] = v

func _add_item(item: Dictionary, start: int, n: int) -> void:
	var s := float(start) + float(item.get("s", n * 0.5))
	var d := float(item.get("d", 0.0))
	match str(item.get("t", "")):
		"crystal":
			var count := int(item.get("n", 1))
			var step := float(item.get("step", 2.0))
			var dd := float(item.get("dd", 0.0))
			for i in count:
				var h := float(item.get("h", 0.0))
				if item.has("arc"):  # an arc over a jump: highest in the middle
					var u := (i + 0.5) / count
					h = float(item["arc"]) * 4.0 * u * (1.0 - u)
				crystals.append({"s": s + i * step, "d": d + i * dd, "h": h})
		"checkpoint":
			checkpoints.append(s)
		"barrier":
			var w := float(item.get("w", 2.0))
			barriers.append({"s0": s - 0.5, "s1": s + 0.5, "d0": d - w * 0.5, "d1": d + w * 0.5})
		"pendulum":
			pendulums.append({
				"s": s, "amp": float(item.get("amp", 2.0)), "period": float(item.get("period", 2.4)),
				"phase": float(item.get("phase", 0.0)), "r": float(item.get("r", 0.8)),
			})
		"gate":
			gates.append({
				"s": s, "period": float(item.get("period", 3.0)), "open": float(item.get("open", 1.6)),
				"phase": float(item.get("phase", 0.0)),
			})
		"boost":
			var w := float(item.get("w", 2.0))
			boosts.append({"s0": s - 1.5, "s1": s + 1.5, "d0": d - w * 0.5, "d1": d + w * 0.5})
		var other:
			problems.append("unknown item '%s'" % other)

## Marks the last row before every gap, so the view can paint a take-off strip there.
func _set_launches() -> void:
	var r := 1
	while r < rows:
		if _row_empty(r) and not _row_empty(r - 1):
			var n := 0
			while r + n < rows and _row_empty(r + n):
				n += 1
			var air := (n + 1.6) / B.SPEED
			launch[r - 1] = B.GRAVITY * air * 0.5
			r += n
		r += 1

func _row_empty(r: int) -> bool:
	for c in B.COLS:
		if cells[r * B.COLS + c] != Cell.NONE:
			return false
	return true

func row_empty(r: int) -> bool:
	return r < 0 or r >= rows or _row_empty(r)

## Where a pendulum's bob is at a given time: across the road, and how fast it is moving.
static func pendulum_d(p: Dictionary, time: float) -> float:
	return p["amp"] * sin(TAU * (time / p["period"] + p["phase"]))

static func pendulum_vd(p: Dictionary, time: float) -> float:
	return p["amp"] * TAU / p["period"] * cos(TAU * (time / p["period"] + p["phase"]))

## 0 = shut, 1 = fully open.
static func gate_open(g: Dictionary, time: float) -> float:
	var t := fposmod(time + g["phase"] * g["period"], g["period"])
	var edge := 0.35
	if t < g["open"]:
		return clampf(minf(t, g["open"] - t) / edge, 0.0, 1.0)
	return 0.0
