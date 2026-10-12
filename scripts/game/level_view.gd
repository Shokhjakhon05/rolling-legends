## Draws a level and a run on it. Everything is built in code from the track data: tiles as
## one MultiMesh, obstacles and pickups as small nodes, scenery placed from a seeded shuffle.
extends Node3D

const B := preload("res://scripts/core/balance.gd")
const Track := preload("res://scripts/core/track.gd")
const Sim := preload("res://scripts/core/sim.gd")
const Skins := preload("res://scripts/game/skins.gd")

const WORLDS := [
	{  # Sky Islands
		"tile_a": Color("ecc977"), "tile_b": Color("dcb45f"), "edge": Color("fbe9b4"), "crack": Color("b98a4a"),
		"ramp": Color("ff9f1c"), "sky_top": Color("1f6fd6"), "sky_horizon": Color("9fd0f7"),
		"ground": Color("7fb8ee"), "fog": 0.0022, "sun": Color("fff3d6"), "sun_energy": 1.35, "ambient": 0.42,
		"accent": Color("e5484d"),
	},
	{  # Desert Canyon
		"tile_a": Color("d98e4a"), "tile_b": Color("c97b3b"), "edge": Color("f3b877"), "crack": Color("8a4a22"),
		"ramp": Color("ffe066"), "sky_top": Color("e8743b"), "sky_horizon": Color("ffd9a0"),
		"ground": Color("a85a30"), "fog": 0.003, "sun": Color("ffd2a0"), "sun_energy": 1.3, "ambient": 0.42,
		"accent": Color("7a3cff"),
	},
	{  # Neon Nights
		"tile_a": Color("27325e"), "tile_b": Color("1e2749"), "edge": Color("22e6ff"), "crack": Color("7a2a8a"),
		"ramp": Color("ff3df0"), "sky_top": Color("060818"), "sky_horizon": Color("3a1a6a"),
		"ground": Color("0a0d22"), "fog": 0.004, "sun": Color("b9c6ff"), "sun_energy": 0.8, "ambient": 0.6,
		"accent": Color("ff3df0"),
	},
]

var track: RefCounted
var sim: RefCounted
var pal: Dictionary
var camera: Camera3D
var ball: MeshInstance3D
var shadow: MeshInstance3D

var _tiles: MultiMesh
var _inst := PackedInt32Array()          # cell index -> instance index, -1 = no tile
var _base: Array[Transform3D] = []       # resting transform of each instance
var _falling := {}                        # instance index -> seconds since it dropped
var _crystals: Array[Node3D] = []
var _pendulums: Array[Node3D] = []
var _gates: Array[Array] = []
var _rings: Array[MeshInstance3D] = []
var _boosts: Array[MeshInstance3D] = []
var _spin := Basis()
var _clock := 0.0
var _cam_pos := Vector3.ZERO
var _cam_ready := false
var _shake := 0.0
var _confetti: CPUParticles3D
var _trail: CPUParticles3D

func setup(t: RefCounted, run: RefCounted, world_index: int, skin: String) -> void:
	track = t
	sim = run
	pal = WORLDS[clampi(world_index, 0, WORLDS.size() - 1)]
	_environment(world_index)
	_build_tiles()
	_build_items()
	_build_scenery(world_index)
	_build_ball(skin)
	camera = Camera3D.new()
	camera.fov = 72.0
	camera.near = 0.2
	camera.far = 400.0
	add_child(camera)
	camera.make_current()
	present(1.0, 0.0)

## Swaps in a fresh run on the same track (restart).
func rebind(run: RefCounted) -> void:
	sim = run
	_falling.clear()
	for i in _base.size():
		_tiles.set_instance_transform(i, _base[i])
	for c in _crystals:
		c.visible = true
	for r in _rings:
		(r.material_override as StandardMaterial3D).albedo_color = Color("ffffff")
		(r.material_override as StandardMaterial3D).emission = Color("ffffff")
	_cam_ready = false

# --- Building -----------------------------------------------------------------------------

func _mat(color: Color, rough: float = 0.8, emission: float = 0.0, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m

func _environment(world_index: int) -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = pal["sky_top"]
	sky_mat.sky_horizon_color = pal["sky_horizon"]
	sky_mat.ground_horizon_color = pal["sky_horizon"]
	sky_mat.ground_bottom_color = pal["ground"]
	sky_mat.sun_angle_max = 12.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = pal["sky_horizon"].lerp(Color.WHITE, 0.5)
	env.ambient_light_energy = pal["ambient"]
	env.fog_enabled = true
	env.fog_light_color = pal["sky_horizon"]
	env.fog_density = pal["fog"]
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = pal["sun"]
	sun.light_energy = pal["sun_energy"]
	sun.rotation_degrees = Vector3(-52.0, 35.0 if world_index != 1 else 70.0, 0.0)
	add_child(sun)

func _tile_basis(row: int) -> Basis:
	var y: float = track.yaw[row]
	var basis := Basis(Vector3.UP, y)
	var p: float = track.pitch[row]
	if p != 0.0:
		basis = Basis(Track.right(y), p) * basis
	# On a bend the rows fan out: stretch the tiles a little so no gaps open on the outside.
	return basis.scaled_local(Vector3(0.97, 1.0, 0.97 + absf(track.curvature[row]) * 4.2))

func _build_tiles() -> void:
	_inst.resize(track.rows * B.COLS)
	_inst.fill(-1)
	var count := 0
	for i in track.cells.size():
		if track.cells[i] != Track.Cell.NONE:
			_inst[i] = count
			count += 1
	var mesh := BoxMesh.new()
	mesh.size = Vector3(B.CELL, 0.5, B.CELL)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.85
	mesh.material = mat
	_tiles = MultiMesh.new()
	_tiles.transform_format = MultiMesh.TRANSFORM_3D
	_tiles.use_colors = true
	_tiles.mesh = mesh
	_tiles.instance_count = count
	_base.resize(count)
	for row in track.rows:
		var basis := _tile_basis(row)
		var first := -1
		var last := -1
		for c in B.COLS:
			if track.cell(row, c) != Track.Cell.NONE:
				if first < 0:
					first = c
				last = c
		var ramp: bool = false
		for k in range(0, 3):
			if row + k < track.rows and track.launch[row + k] > 0.0:
				ramp = true
		var finish: bool = row >= track.rows - B.FINISH_PAD
		for c in B.COLS:
			var i: int = row * B.COLS + c
			if _inst[i] < 0:
				continue
			var kind: int = track.cells[i]
			var color: Color = pal["tile_a"] if (row + c) % 2 == 0 else pal["tile_b"]
			if c == first or c == last:
				color = color.lerp(pal["edge"], 0.75)
			if ramp:
				color = pal["ramp"] if (row + c) % 2 == 0 else pal["ramp"].darkened(0.25)
			if finish:
				color = Color("f5f5f5") if (row + c) % 2 == 0 else Color("20242c")
			var drop := -0.25
			if kind == Track.Cell.CRUMBLE:
				color = pal["crack"] if (row + c) % 2 == 0 else pal["crack"].darkened(0.2)
				drop = -0.31
			var xf := Transform3D(basis, track.to_world(row + 0.5, Track.d_of(c), drop))
			_base[_inst[i]] = xf
			_tiles.set_instance_transform(_inst[i], xf)
			_tiles.set_instance_color(_inst[i], color)
	var node := MultiMeshInstance3D.new()
	node.multimesh = _tiles
	# The road is longer than any sensible bounding box guess; never cull it as a whole.
	node.custom_aabb = AABB(Vector3(-2000, -200, -2000), Vector3(4000, 400, 4000))
	add_child(node)

func _place(node: Node3D, s: float, d: float, h: float) -> void:
	add_child(node)
	node.position = track.to_world(s, d, h)
	node.rotation.y = track.yaw_at(s)

func _build_items() -> void:
	var gem := SphereMesh.new()
	gem.radius = 0.42
	gem.height = 0.95
	gem.radial_segments = 4
	gem.rings = 1
	var gem_mat := _mat(Color("39e6ff"), 0.15, 1.3, 0.3)
	for c in track.crystals:
		var n := MeshInstance3D.new()
		n.mesh = gem
		n.material_override = gem_mat
		_place(n, c["s"], c["d"], c["h"] + 0.85)
		_crystals.append(n)

	var red := _mat(pal["accent"], 0.6)
	var white := _mat(Color("f4f4f4"), 0.6)
	for b in track.barriers:
		var w: float = b["d1"] - b["d0"]
		var n := Node3D.new()
		var body := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(w, 1.1, 0.9)
		body.mesh = bm
		body.material_override = red
		body.position.y = 0.55
		n.add_child(body)
		var cap := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(w + 0.1, 0.22, 1.0)
		cap.mesh = cm
		cap.material_override = white
		cap.position.y = 1.2
		n.add_child(cap)
		_place(n, (b["s0"] + b["s1"]) * 0.5, (b["d0"] + b["d1"]) * 0.5, 0.0)

	var steel := _mat(Color("8f9bb0"), 0.4, 0.0, 0.7)
	for p in track.pendulums:
		var n := Node3D.new()
		var span: float = p["amp"] + 1.6
		for side in [-1.0, 1.0]:
			var post := MeshInstance3D.new()
			var pm := BoxMesh.new()
			pm.size = Vector3(0.3, 4.6, 0.3)
			post.mesh = pm
			post.material_override = steel
			post.position = Vector3(side * span, 2.3, 0)
			n.add_child(post)
		var beam := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(span * 2.0 + 0.3, 0.3, 0.3)
		beam.mesh = bm
		beam.material_override = steel
		beam.position.y = 4.5
		n.add_child(beam)
		var pivot := Node3D.new()
		pivot.position.y = 4.4
		n.add_child(pivot)
		var arm := MeshInstance3D.new()
		var am := BoxMesh.new()
		am.size = Vector3(0.14, 3.6, 0.14)
		arm.mesh = am
		arm.material_override = steel
		arm.position.y = -1.8
		pivot.add_child(arm)
		var bob := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = p["r"]
		sm.height = p["r"] * 2.0
		bob.mesh = sm
		bob.material_override = red
		bob.position.y = -3.65
		pivot.add_child(bob)
		_place(n, p["s"], 0.0, 0.0)
		_pendulums.append(pivot)

	for g in track.gates:
		var n := Node3D.new()
		var leaves := []
		for side in [-1.0, 1.0]:
			var leaf := MeshInstance3D.new()
			var lm := BoxMesh.new()
			lm.size = Vector3(1.0, 1.7, 0.45)
			leaf.mesh = lm
			leaf.material_override = red
			leaf.position.y = 0.85
			n.add_child(leaf)
			leaves.append(leaf)
			var post := MeshInstance3D.new()
			var pm := BoxMesh.new()
			pm.size = Vector3(0.4, 2.4, 0.7)
			post.mesh = pm
			post.material_override = steel
			post.position = Vector3(side * (B.COLS * 0.5 + 0.2), 1.2, 0)
			n.add_child(post)
		_place(n, g["s"], 0.0, 0.0)
		_gates.append(leaves)

	for b in track.boosts:
		var n := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(b["d1"] - b["d0"], 0.06, b["s1"] - b["s0"])
		n.mesh = bm
		n.material_override = _mat(Color("7dff5a"), 0.3, 1.6)
		_place(n, (b["s0"] + b["s1"]) * 0.5, (b["d0"] + b["d1"]) * 0.5, 0.04)
		_boosts.append(n)

	var torus := TorusMesh.new()
	torus.inner_radius = 2.9
	torus.outer_radius = 3.2
	torus.rings = 32
	torus.ring_segments = 8
	for cp in track.checkpoints:
		var n := MeshInstance3D.new()
		n.mesh = torus
		n.material_override = _mat(Color("ffffff"), 0.3, 0.9)
		_place(n, cp, 0.0, 1.0)
		n.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		_rings.append(n)

	# Finish arch.
	var arch := Node3D.new()
	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.5, 5.0, 0.5)
		post.mesh = pm
		post.material_override = white
		post.position = Vector3(side * 3.6, 2.5, 0)
		arch.add_child(post)
	var banner := MeshInstance3D.new()
	var bm2 := BoxMesh.new()
	bm2.size = Vector3(7.7, 1.2, 0.3)
	banner.mesh = bm2
	banner.material_override = _mat(Color("ffd23f"), 0.5, 0.6)
	banner.position.y = 4.6
	arch.add_child(banner)
	_place(arch, track.finish_s, 0.0, 0.0)
	_confetti = CPUParticles3D.new()
	_confetti.emitting = false
	_confetti.one_shot = true
	_confetti.amount = 90
	_confetti.lifetime = 2.2
	_confetti.explosiveness = 0.9
	_confetti.direction = Vector3.UP
	_confetti.spread = 50.0
	_confetti.initial_velocity_min = 7.0
	_confetti.initial_velocity_max = 13.0
	_confetti.gravity = Vector3(0, -12, 0)
	var cmesh := BoxMesh.new()
	cmesh.size = Vector3(0.18, 0.18, 0.04)
	var cmat := StandardMaterial3D.new()
	cmat.vertex_color_use_as_albedo = true
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cmesh.material = cmat
	_confetti.mesh = cmesh
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color("ff5d73"), Color("ffd23f"), Color("3ddc97"), Color("4ea8ff")])
	ramp.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
	_confetti.color_initial_ramp = ramp
	_place(_confetti, track.finish_s + 1.0, 0.0, 1.0)

func _build_scenery(world_index: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(track.id) + 17
	var mats := [_mat(Color("7a5a3a")), _mat(Color("5fbf4a")), _mat(Color("ffffff"), 1.0, 0.25)]
	if world_index == 1:
		mats = [_mat(Color("b5653a")), _mat(Color("d98e4a")), _mat(Color("ffe2b8"), 1.0, 0.2)]
	elif world_index == 2:
		mats = [_mat(Color("141a33")), _mat(Color("22e6ff"), 0.4, 2.0), _mat(Color("ff3df0"), 0.4, 2.0)]
	var row := 4
	while row < track.rows:
		for side in [-1.0, 1.0]:
			if rng.randf() < 0.25:
				continue
			var off: float = side * rng.randf_range(15.0, 46.0)
			var at: Vector3 = track.to_world(row, off, 0.0)
			var n := Node3D.new()
			add_child(n)
			match world_index:
				0:
					var r := rng.randf_range(4.0, 9.0)
					n.position = at + Vector3(0, rng.randf_range(-16.0, -3.0), 0)
					var rock := MeshInstance3D.new()
					var cone := CylinderMesh.new()
					cone.top_radius = r
					cone.bottom_radius = r * 0.15
					cone.height = r * 1.5
					cone.radial_segments = 9
					rock.mesh = cone
					rock.material_override = mats[0]
					rock.position.y = -cone.height * 0.5
					n.add_child(rock)
					var top := MeshInstance3D.new()
					var disc := CylinderMesh.new()
					disc.top_radius = r * 0.96
					disc.bottom_radius = r * 1.03
					disc.height = 0.7
					disc.radial_segments = 9
					top.mesh = disc
					top.material_override = mats[1]
					top.position.y = 0.3
					n.add_child(top)
					if rng.randf() < 0.7:
						var cloud := MeshInstance3D.new()
						var cs := SphereMesh.new()
						cs.radius = rng.randf_range(4.0, 8.0)
						cs.height = cs.radius * 0.9
						cs.radial_segments = 10
						cs.rings = 5
						cloud.mesh = cs
						cloud.material_override = mats[2]
						cloud.position = Vector3(rng.randf_range(-10, 10), rng.randf_range(-14, -4), rng.randf_range(-10, 10))
						n.add_child(cloud)
				1:
					var h := rng.randf_range(30.0, 70.0)
					var r2 := rng.randf_range(4.0, 9.0)
					var mesa := MeshInstance3D.new()
					var cm := CylinderMesh.new()
					cm.top_radius = r2
					cm.bottom_radius = r2 * 1.5
					cm.height = h
					cm.radial_segments = 7
					mesa.mesh = cm
					mesa.material_override = mats[rng.randi() % 2]
					n.position = at + Vector3(0, rng.randf_range(-6.0, 8.0) - h * 0.5, 0)
					n.add_child(mesa)
				_:
					var h2 := rng.randf_range(30.0, 90.0)
					var w := rng.randf_range(5.0, 9.0)
					var tower := MeshInstance3D.new()
					var tm := BoxMesh.new()
					tm.size = Vector3(w, h2, w)
					tower.mesh = tm
					tower.material_override = mats[0]
					n.position = at + Vector3(0, rng.randf_range(0.0, 18.0) - h2 * 0.5, 0)
					n.rotation.y = rng.randf() * TAU
					n.add_child(tower)
					var lines := rng.randi_range(2, 4)
					for k in lines:
						var strip := MeshInstance3D.new()
						var sm := BoxMesh.new()
						sm.size = Vector3(w + 0.2, 0.5, w + 0.2)
						strip.mesh = sm
						strip.material_override = mats[1 + (k + rng.randi()) % 2]
						strip.position.y = h2 * 0.5 - 3.0 - k * rng.randf_range(4.0, 9.0)
						n.add_child(strip)
		row += rng.randi_range(9, 16)

func _build_ball(skin: String) -> void:
	ball = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = B.BALL_RADIUS
	sm.height = B.BALL_RADIUS * 2.0
	sm.radial_segments = 28
	sm.rings = 14
	ball.mesh = sm
	ball.material_override = Skins.material(skin)
	add_child(ball)
	shadow = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.55
	disc.bottom_radius = 0.55
	disc.height = 0.01
	disc.radial_segments = 18
	shadow.mesh = disc
	var sh := StandardMaterial3D.new()
	sh.albedo_color = Color(0, 0, 0, 0.35)
	sh.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sh.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow.material_override = sh
	add_child(shadow)
	_trail = CPUParticles3D.new()
	_trail.amount = 24
	_trail.lifetime = 0.45
	_trail.local_coords = false
	_trail.direction = Vector3.UP
	_trail.spread = 40.0
	_trail.initial_velocity_min = 0.6
	_trail.initial_velocity_max = 1.6
	_trail.gravity = Vector3(0, -3, 0)
	_trail.scale_amount_min = 0.5
	_trail.scale_amount_max = 1.0
	var tmesh := SphereMesh.new()
	tmesh.radius = 0.09
	tmesh.height = 0.18
	tmesh.radial_segments = 6
	tmesh.rings = 3
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color("7dff5a")
	tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tmesh.material = tmat
	_trail.mesh = tmesh
	_trail.emitting = false
	add_child(_trail)

func set_skin(skin: String) -> void:
	ball.material_override = Skins.material(skin)

# --- Per frame ----------------------------------------------------------------------------

## Reacts to something the run reported.
func on_event(e: Dictionary) -> void:
	match e["t"]:
		"crystal":
			_crystals[e["i"]].visible = false
		"crumble":
			var i: int = _inst[e["row"] * B.COLS + e["col"]]
			if i >= 0:
				_falling[i] = 0.0
		"collapse":
			for c in B.COLS:
				var i: int = _inst[e["row"] * B.COLS + c]
				if i >= 0 and not _falling.has(i):
					_falling[i] = -0.06 * absf(c - 3.0)
		"checkpoint":
			var m := _rings[e["i"]].material_override as StandardMaterial3D
			m.albedo_color = Color("3ddc97")
			m.emission = Color("3ddc97")
		"respawn":
			_falling.clear()
			var first: int = sim.behind_row * B.COLS
			for cell in range(first, _inst.size()):
				if _inst[cell] >= 0:
					_tiles.set_instance_transform(_inst[cell], _base[_inst[cell]])
			_cam_ready = false
		"hit":
			_shake = 0.35
		"win":
			_confetti.restart()
			_confetti.emitting = true

## Draws the run. [s], [d], [h] are the ball's (interpolated) road coordinates.
func present(delta: float, steer: float, s: float = -1.0, d: float = 0.0, h: float = 0.0) -> void:
	if s < 0.0:
		s = sim.s
		d = sim.d
		h = sim.h
	_clock += delta
	var yaw: float = track.yaw_at(s)
	var fwd := Track.forward(yaw)
	var rgt := Track.right(yaw)
	var p: Vector3 = track.to_world(s, d, h + B.BALL_RADIUS)
	ball.position = p
	_spin = Basis(rgt, -sim.vs * delta / B.BALL_RADIUS) * Basis(fwd, sim.vd * delta / B.BALL_RADIUS) * _spin
	ball.basis = _spin.orthonormalized()
	shadow.visible = h > -0.3 and sim.solid_at(s, d)
	shadow.position = track.to_world(s, d, 0.02)
	var squash := clampf(1.0 - h * 0.12, 0.45, 1.0)
	shadow.scale = Vector3(squash, 1.0, squash)
	_trail.position = p - Vector3(0, B.BALL_RADIUS * 0.6, 0)
	_trail.emitting = sim.boost_left > 0.0 and sim.state == Sim.State.RUNNING

	# Camera: behind and above, leaning a little towards where the ball is heading.
	var back := 8.6
	var cam_s := s - back
	var target: Vector3
	if cam_s >= 0.0:
		target = track.to_world(cam_s, d * 0.55, 5.4)
	else:
		target = track.to_world(0.0, d * 0.55, 5.4) + Track.forward(track.yaw[0]) * cam_s
	var falling: bool = sim.state == Sim.State.FALLING or sim.state == Sim.State.LOST
	if falling:
		target = _cam_pos  # stay and watch the ball go
	if not _cam_ready:
		_cam_pos = target
		_cam_ready = true
	_cam_pos = _cam_pos.lerp(target, 1.0 - exp(-10.0 * delta))
	var look: Vector3 = track.to_world(s + 7.0, d * 0.6, 0.4)
	if falling:
		look = p
	_shake = maxf(_shake - delta, 0.0)
	var jitter := Vector3(sin(_clock * 63.0), cos(_clock * 71.0), 0.0) * _shake * 0.35
	camera.position = _cam_pos + jitter
	camera.look_at(look, Vector3.UP)
	camera.fov = lerpf(camera.fov, 72.0 + (9.0 if sim.boost_left > 0.0 else 0.0), 1.0 - exp(-4.0 * delta))

	# Things that move on their own clock.
	for i in _crystals.size():
		if _crystals[i].visible:
			_crystals[i].rotation.y = _clock * 2.4 + i
	for i in _pendulums.size():
		var pd: float = Track.pendulum_d(track.pendulums[i], sim.time)
		_pendulums[i].rotation.z = asin(clampf(pd / 3.65, -1.0, 1.0))
	for i in _gates.size():
		var open: float = Track.gate_open(track.gates[i], sim.time)
		var half := B.COLS * 0.5
		var gap := half * open
		for k in 2:
			var side := -1.0 if k == 0 else 1.0
			var leaf: MeshInstance3D = _gates[i][k]
			leaf.scale.x = maxf(half - gap, 0.02)
			leaf.position.x = side * (half + gap) * 0.5
	for b in _boosts:
		(b.material_override as StandardMaterial3D).emission_energy_multiplier = 1.3 + 0.7 * sin(_clock * 8.0)

	# Cracked tiles ahead tremble before they go.
	var from := int(floor(s + B.CRUMBLE_FALL))
	var to := mini(int(floor(s + B.CRUMBLE_WARN)), track.rows - 1)
	for row in range(maxi(from, 0), to + 1):
		for c in B.COLS:
			var cell := row * B.COLS + c
			if track.cells[cell] == Track.Cell.CRUMBLE and sim.fallen[cell] == 0:
				var i := _inst[cell]
				var near := 1.0 - float(row - from) / maxf(float(to - from), 1.0)
				var xf := _base[i]
				xf.origin += Vector3(sin(_clock * 47.0 + row), sin(_clock * 39.0 + c) * 0.6, cos(_clock * 43.0 + c)) * 0.05 * near
				_tiles.set_instance_transform(i, xf)
	# Dropped tiles fall, shrink and disappear.
	var done := []
	for i in _falling:
		var t: float = _falling[i] + delta
		_falling[i] = t
		if t < 0.0:
			continue
		var xf := _base[i]
		xf.origin.y -= 14.0 * t * t
		xf.basis = xf.basis.rotated(xf.basis.x.normalized(), t * 2.2).scaled_local(Vector3.ONE * maxf(1.0 - t * 0.9, 0.001))
		_tiles.set_instance_transform(i, xf)
		if t > 1.1:
			done.append(i)
	for i in done:
		_falling.erase(i)
		var xf := _base[i]
		xf.basis = xf.basis.scaled_local(Vector3.ONE * 0.001)
		xf.origin.y -= 60.0
		_tiles.set_instance_transform(i, xf)
