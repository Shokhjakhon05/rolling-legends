## Draws a level and a run on it. Everything is built in code from the track data: tiles as
## one MultiMesh, obstacles and pickups as small nodes, scenery placed from a seeded shuffle.
extends Node3D

const B := preload("res://scripts/core/balance.gd")
const Track := preload("res://scripts/core/track.gd")
const Sim := preload("res://scripts/core/sim.gd")
const Skins := preload("res://scripts/game/skins.gd")

const WORLDS := [
	{  # Sky Islands
		"tile_a": Color("d9a443"), "tile_b": Color("c08a32"), "edge": Color("f0c96a"), "crack": Color("8a5a2c"),
		"ramp": Color("ff7a1c"), "sky_top": Color("1257c4"), "sky_horizon": Color("7fbcf2"),
		"ground": Color("5fa3e6"), "fog": 0.0016, "sun": Color("fff0cf"), "sun_energy": 0.95, "ambient": 0.3,
		"accent": Color("e5484d"),
	},
	{  # Desert Canyon
		"tile_a": Color("d98e4a"), "tile_b": Color("c97b3b"), "edge": Color("f3b877"), "crack": Color("8a4a22"),
		"ramp": Color("ffe066"), "sky_top": Color("e8743b"), "sky_horizon": Color("ffd9a0"),
		"ground": Color("a85a30"), "fog": 0.003, "sun": Color("ffd2a0"), "sun_energy": 1.05, "ambient": 0.38,
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
var _keels: Array[Array] = []           # [row, node]: supports under the road
var _burst: CPUParticles3D
var _dust: CPUParticles3D
var _streak: CPUParticles3D
var _streak_mat: StandardMaterial3D
var _squash := 0.0

var world := 0

func setup(t: RefCounted, run: RefCounted, world_index: int, skin: String) -> void:
	track = t
	sim = run
	world = world_index
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
	for k in _keels:
		k[1].visible = true
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
	m.metallic_specular = 0.5 if metal > 0.0 else 0.12   # matte things must not mirror the sky
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
	env.ambient_light_color = pal["sky_horizon"].lerp(Color.WHITE, 0.25)
	env.ambient_light_energy = pal["ambient"]
	env.fog_enabled = true
	env.fog_light_color = pal["sky_horizon"]
	env.fog_density = pal["fog"]
	env.fog_sky_affect = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 9.0
	env.glow_enabled = true
	env.glow_intensity = 0.38
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.35
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = pal["sun"]
	sun.light_energy = pal["sun_energy"]
	sun.rotation_degrees = Vector3(-52.0, 35.0 if world_index != 1 else 70.0, 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 42.0
	sun.shadow_bias = 0.06
	sun.shadow_opacity = 0.7
	add_child(sun)

func _tile_basis(row: int) -> Basis:
	var y: float = track.yaw[row]
	var basis := Basis(Vector3.UP, y)
	var p: float = track.pitch[row]
	if p != 0.0:
		basis = Basis(Track.right(y), p) * basis
	# On a bend the rows fan out: stretch the tiles a little so no gaps open on the outside.
	return basis.scaled_local(Vector3(0.97, 1.0, 0.97 + absf(track.curvature[row]) * 4.2))

const TILE_DEPTH := 1.0

## One stone slab: a paler face inside a darker joint, a little grain, a few scratches. Drawn
## once per world and tinted per tile through the instance colour.
func _tile_material(world_index: int) -> StandardMaterial3D:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var grain := FastNoiseLite.new()
	grain.seed = 11 + world_index
	grain.frequency = 0.045
	var rng := RandomNumberGenerator.new()
	rng.seed = 5 + world_index
	for y in n:
		for x in n:
			var edge: int = mini(mini(x, y), mini(n - 1 - x, n - 1 - y))
			var v := 0.9 + grain.get_noise_2d(x, y) * 0.09
			if edge < 3:
				v *= 0.5      # the joint between slabs
			elif edge < 7:
				v *= 1.12     # a lit bevel just inside it
			img.set_pixel(x, y, Color(v, v, v))
	for k in 5:
		var p := Vector2(rng.randf_range(12, n - 12), rng.randf_range(12, n - 12))
		var dir := Vector2.from_angle(rng.randf() * TAU)
		for step in rng.randi_range(8, 26):
			p += dir + Vector2(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6))
			if p.x > 8 and p.y > 8 and p.x < n - 8 and p.y < n - 8:
				img.set_pixelv(Vector2i(p), img.get_pixelv(Vector2i(p)) * 0.82)
	img.generate_mipmaps()
	var bumps := NoiseTexture2D.new()
	bumps.width = 128
	bumps.height = 128
	bumps.seamless = true
	bumps.as_normal_map = true
	bumps.bump_strength = 5.0
	var bn := FastNoiseLite.new()
	bn.frequency = 0.06
	bumps.noise = bn
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.uv1_triplanar = true
	mat.uv1_offset = Vector3(0.5, 0.5, 0.5)
	mat.normal_enabled = true
	mat.normal_texture = bumps
	mat.normal_scale = 0.6
	mat.roughness = 0.42 if world_index == 2 else 0.78
	mat.metallic = 0.35 if world_index == 2 else 0.0
	return mat

func _build_tiles() -> void:
	_inst.resize(track.rows * B.COLS)
	_inst.fill(-1)
	var count := 0
	for i in track.cells.size():
		if track.cells[i] != Track.Cell.NONE:
			_inst[i] = count
			count += 1
	var mesh := BoxMesh.new()
	mesh.size = Vector3(B.CELL, TILE_DEPTH, B.CELL)
	mesh.material = _tile_material(world)
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
				color = color.lerp(pal["edge"], 0.6)
			if ramp:
				color = pal["ramp"] if (row + c) % 2 == 0 else pal["ramp"].darkened(0.25)
			if finish:
				color = Color("f5f5f5") if (row + c) % 2 == 0 else Color("20242c")
			var drop := -TILE_DEPTH * 0.5
			if (c == first or c == last) and not ramp and not finish and kind == Track.Cell.SOLID:
				drop += 0.07   # border stones stand a little proud of the road
			if kind == Track.Cell.CRUMBLE:
				color = pal["crack"] if (row + c) % 2 == 0 else pal["crack"].darkened(0.2)
				drop -= 0.07
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
	var gem_mat := _mat(Color("12c8ff"), 0.12, 0.75, 0.4)
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

## Low-poly look: every face gets its own normal, so shapes read as cut stone, not as blobs.
func _faceted(mesh: PrimitiveMesh) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.create_from(mesh, 0)
	st.deindex()
	st.generate_normals()
	return st.commit()

func _prop(parent: Node3D, mesh: Mesh, mat: Material, at: Vector3, scale: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = at
	m.scale = scale
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	return m

func _window_texture(rng: RandomNumberGenerator, a: Color, b: Color) -> ImageTexture:
	var img := Image.create(32, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color.BLACK)
	for y in range(2, 62, 4):
		for x in range(2, 30, 4):
			if rng.randf() < 0.45:
				img.fill_rect(Rect2i(x, y, 2, 2), a if rng.randf() < 0.6 else b)
	return ImageTexture.create_from_image(img)

func _build_scenery(world_index: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(track.id) + 17
	var cone := CylinderMesh.new()
	cone.top_radius = 1.0
	cone.bottom_radius = 0.12
	cone.height = 1.0
	cone.radial_segments = 7
	cone.rings = 1
	var rock_mesh := _faceted(cone)
	var disc := CylinderMesh.new()
	disc.top_radius = 0.96
	disc.bottom_radius = 1.04
	disc.height = 1.0
	disc.radial_segments = 7
	disc.rings = 1
	var cap_mesh := _faceted(disc)
	var tree_top := CylinderMesh.new()
	tree_top.top_radius = 0.0
	tree_top.bottom_radius = 1.0
	tree_top.height = 1.0
	tree_top.radial_segments = 6
	tree_top.rings = 1
	var tree_mesh := _faceted(tree_top)
	var puff := SphereMesh.new()
	puff.radius = 1.0
	puff.height = 1.5
	puff.radial_segments = 8
	puff.rings = 4
	var puff_mesh := _faceted(puff)
	var cube := BoxMesh.new()

	var rock := _mat(Color("6f5a4a"), 0.95)
	var rock2 := _mat(Color("8a6f58"), 0.95)
	var grass := _mat(Color("5cc24a"), 0.9)
	var leaf := _mat(Color("2f9a4a"), 0.9)
	var trunk := _mat(Color("6b4a2c"), 0.9)
	var cloud := _mat(Color("ffffff"), 1.0, 0.18)
	var sand_a := _mat(Color("c8743c"), 0.95)
	var sand_b := _mat(Color("e09a58"), 0.95)
	var sand_c := _mat(Color("9c5230"), 0.95)
	var cactus := _mat(Color("3f8f4a"), 0.9)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("10152c")
	dark.roughness = 0.5
	dark.metallic = 0.4
	var lit: Array[StandardMaterial3D] = []
	if world_index == 2:
		for k in 3:
			var m := StandardMaterial3D.new()
			m.albedo_color = Color("0c1024")
			m.emission_enabled = true
			m.emission_texture = _window_texture(rng, Color("22e6ff"), Color("ff3df0") if k != 1 else Color("ffd23f"))
			m.emission_energy_multiplier = 2.2
			m.uv1_scale = Vector3(3, 3, 1)
			lit.append(m)
	var neon_a := _mat(Color("22e6ff"), 0.4, 2.6)
	var neon_b := _mat(Color("ff3df0"), 0.4, 2.6)

	var row := 2
	while row < track.rows:
		for side in [-1.0, 1.0]:
			if rng.randf() < 0.2:
				continue
			var off: float = side * rng.randf_range(13.0, 48.0)
			var n := Node3D.new()
			add_child(n)
			n.position = track.to_world(row, off, 0.0)
			n.rotation.y = rng.randf() * TAU
			match world_index:
				0:
					var r := rng.randf_range(4.0, 9.5)
					n.position.y += rng.randf_range(-15.0, -2.5)
					_prop(n, rock_mesh, rock, Vector3(0, -r * 0.75, 0), Vector3(r, r * 1.5, r))
					_prop(n, rock_mesh, rock2, Vector3(r * 0.3, -r * 0.4, r * 0.2), Vector3(r * 0.55, r * 0.8, r * 0.55))
					_prop(n, cap_mesh, grass, Vector3(0, 0.25, 0), Vector3(r, 0.7, r))
					for k in rng.randi_range(1, 4):
						var tp := Vector3(rng.randf_range(-0.6, 0.6) * r, 0.6, rng.randf_range(-0.6, 0.6) * r)
						var th := rng.randf_range(1.6, 3.2)
						_prop(n, cap_mesh, trunk, tp + Vector3(0, th * 0.2, 0), Vector3(0.22, th * 0.5, 0.22))
						_prop(n, tree_mesh, leaf, tp + Vector3(0, th * 0.75, 0), Vector3(th * 0.42, th, th * 0.42))
						_prop(n, tree_mesh, grass, tp + Vector3(0, th * 1.15, 0), Vector3(th * 0.3, th * 0.7, th * 0.3))
					if rng.randf() < 0.75:
						var c := Vector3(rng.randf_range(-12, 12), rng.randf_range(-13, -5), rng.randf_range(-12, 12))
						for k in rng.randi_range(3, 5):
							var cr := rng.randf_range(2.5, 5.5)
							_prop(n, puff_mesh, cloud, c + Vector3(rng.randf_range(-5, 5), rng.randf_range(-0.6, 0.6), rng.randf_range(-3, 3)), Vector3(cr, cr * 0.62, cr))
				1:
					# A mesa in bands of rock, like cut sandstone.
					var r := rng.randf_range(4.5, 9.0)
					n.position.y += rng.randf_range(2.0, 12.0)
					var bands := rng.randi_range(4, 6)
					var top := 0.0
					for k in bands:
						var bh := rng.randf_range(4.0, 9.0) if k < bands - 1 else 60.0
						var grow := 1.0 + k * 0.13
						_prop(n, cap_mesh, [sand_b, sand_a, sand_c][k % 3], Vector3(0, top - bh * 0.5, 0), Vector3(r * grow, bh, r * grow))
						top -= bh
					if rng.randf() < 0.5:
						var cp := Vector3(rng.randf_range(-0.5, 0.5) * r, 2.0, rng.randf_range(-0.5, 0.5) * r)
						_prop(n, cap_mesh, cactus, cp, Vector3(0.4, 3.0, 0.4))
						_prop(n, cap_mesh, cactus, cp + Vector3(0.8, 0.4, 0), Vector3(0.28, 1.4, 0.28))
				_:
					var h2 := rng.randf_range(34.0, 95.0)
					var w := rng.randf_range(5.0, 9.5)
					n.position.y += rng.randf_range(2.0, 22.0) - h2 * 0.5
					n.rotation.y = track.yaw_at(row) + (0.0 if rng.randf() < 0.5 else PI * 0.5)
					_prop(n, cube, lit[rng.randi() % lit.size()], Vector3.ZERO, Vector3(w, h2, w))
					_prop(n, cube, dark, Vector3(0, h2 * 0.5 + 0.6, 0), Vector3(w * 0.7, 1.2, w * 0.7))
					_prop(n, cube, neon_a if rng.randf() < 0.5 else neon_b, Vector3(0, h2 * 0.5 + 0.05, 0), Vector3(w + 0.25, 0.3, w + 0.25))
					if rng.randf() < 0.5:
						_prop(n, cube, neon_b if rng.randf() < 0.5 else neon_a, Vector3(0, h2 * 0.5 + 5.0, 0), Vector3(0.18, 9.0, 0.18))
		row += rng.randi_range(8, 14)

	# Under the road: something for it to rest on, so it does not look like a strip of paper.
	var keel_mat := rock if world_index == 0 else (sand_c if world_index == 1 else dark)
	var r2 := 3
	while r2 < track.rows - 2:
		if not track.row_empty(r2) and not track.row_empty(r2 + 1):
			var k := Node3D.new()
			add_child(k)
			k.position = track.to_world(r2 + 0.5, 0.0, -TILE_DEPTH)
			k.rotation.y = track.yaw_at(r2 + 0.5)
			var wide := 0.0
			for c in B.COLS:
				if track.cell(r2, c) != Track.Cell.NONE:
					wide += 1.0
			if world_index == 1:
				_prop(k, cap_mesh, keel_mat, Vector3(0, -30.0, 0), Vector3(wide * 0.3, 60.0, wide * 0.3))
			elif world_index == 0:
				_prop(k, rock_mesh, keel_mat, Vector3(0, -2.2, 0), Vector3(wide * 0.5, 4.4, 2.6))
			else:
				_prop(k, cube, dark, Vector3(0, -0.5, 0), Vector3(wide * 0.6, 1.0, 6.0))
				_prop(k, cube, neon_a, Vector3(0, -1.05, 0), Vector3(wide * 0.62, 0.12, 6.0))
			_keels.append([r2, k])
		r2 += 6

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
	_burst = _make_burst(Color("7df3ff"), 18, 5.5)
	_dust = _make_burst(pal["edge"], 10, 2.4)
	# A soft streak behind the ball, in the ball's own colour.
	_streak = CPUParticles3D.new()
	_streak.amount = 30
	_streak.lifetime = 0.38
	_streak.local_coords = false
	_streak.gravity = Vector3.ZERO
	_streak.initial_velocity_max = 0.2
	_streak.scale_amount_min = 1.0
	_streak.scale_amount_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	_streak.scale_amount_curve = curve
	var smesh := SphereMesh.new()
	smesh.radius = 0.2
	smesh.height = 0.4
	smesh.radial_segments = 8
	smesh.rings = 4
	_streak_mat = StandardMaterial3D.new()
	_streak_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_streak_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smesh.material = _streak_mat
	_streak.mesh = smesh
	add_child(_streak)
	_tint_streak(skin)

func _tint_streak(skin: String) -> void:
	var c: Color = Skins.colors(skin)["b"]
	_streak_mat.albedo_color = Color(c.r, c.g, c.b, 0.3)

func _make_burst(color: Color, amount: int, speed: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.5
	p.explosiveness = 1.0
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 75.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -9, 0)
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.14, 0.14, 0.14)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	p.mesh = mesh
	add_child(p)
	return p

func set_skin(skin: String) -> void:
	ball.material_override = Skins.material(skin)
	_tint_streak(skin)

# --- Per frame ----------------------------------------------------------------------------

## Reacts to something the run reported.
func on_event(e: Dictionary) -> void:
	match e["t"]:
		"crystal":
			_crystals[e["i"]].visible = false
			_burst.position = _crystals[e["i"]].position
			_burst.restart()
		"land":
			_dust.position = ball.position - Vector3(0, B.BALL_RADIUS, 0)
			_dust.restart()
			_squash = 1.0
		"launch":
			_squash = -1.0
		"crumble":
			var i: int = _inst[e["row"] * B.COLS + e["col"]]
			if i >= 0:
				_falling[i] = 0.0
		"collapse":
			for k in _keels:
				if k[0] == e["row"]:
					k[1].visible = false
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
			for k in _keels:
				k[1].visible = k[0] >= sim.behind_row
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
	# A touch of squash on landing and stretch on take-off.
	_squash = move_toward(_squash, 0.0, delta * 5.0)
	var sy := 1.0 - _squash * 0.22
	var sxz := 1.0 + _squash * 0.12
	ball.basis = Basis.from_scale(Vector3(sxz, sy, sxz)) * _spin.orthonormalized()
	_streak.position = p
	_streak.emitting = sim.state == Sim.State.RUNNING and sim.vs > 4.0
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
