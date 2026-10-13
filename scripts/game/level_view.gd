## Draws a level and a run on it. Everything is built in code from the track data: tiles as
## one MultiMesh, obstacles and pickups as small nodes, scenery placed from a seeded shuffle.
extends Node3D

const B := preload("res://scripts/core/balance.gd")
const Track := preload("res://scripts/core/track.gd")
const Sim := preload("res://scripts/core/sim.gd")
const Skins := preload("res://scripts/game/skins.gd")
const Props := preload("res://scripts/game/props.gd")

const WORLDS := [
	{  # Sky Islands
		"tile_a": Color("efe3c8"), "tile_b": Color("d6c6a2"), "edge": Color("f2b93a"), "crack": Color("8a5a2c"),
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
var ball: Node3D
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
var _painted := false                   # the road shader is in use: instance alpha = paint strength

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
	if world_index < SKY_PANORAMA.size() and ResourceLoader.exists(SKY_PANORAMA[world_index]):
		var pano := PanoramaSkyMaterial.new()
		pano.panorama = load(SKY_PANORAMA[world_index])
		pano.energy_multiplier = 1.0
		sky.sky_material = pano
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
const STONE := [["res://assets/tex/sky_stone_diff.jpg", "res://assets/tex/sky_stone_nor.jpg"]]
const SKY_PANORAMA := ["res://assets/tex/sky_day.jpg"]

## Worlds that have a real stone texture use the road shader; the others keep the drawn slab.
func _tile_material(world_index: int) -> Material:
	if world_index < STONE.size() and ResourceLoader.exists(STONE[world_index][0]):
		var sm := ShaderMaterial.new()
		sm.shader = load("res://assets/road.gdshader")
		sm.set_shader_parameter("stone", load(STONE[world_index][0]))
		sm.set_shader_parameter("stone_normal", load(STONE[world_index][1]))
		sm.set_shader_parameter("scale", 0.28)
		sm.set_shader_parameter("roughness", 0.82)
		_painted = true
		return sm
	return _drawn_tile_material(world_index)

func _drawn_tile_material(world_index: int) -> StandardMaterial3D:
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
			# With the stone shader plain slabs are only tinted; special ones are painted over.
			var special: bool = ramp or finish or kind == Track.Cell.CRUMBLE
			color.a = 0.95 if special else (0.9 if (c == first or c == last) else 0.32)
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
		if world < 2 and Props.has("temple_ruins"):
			var gate := Props.make("temple_ruins", "Stone_Archway", 12.5, 0, Color.WHITE if world == 0 else Color(1.55, 1.02, 0.62))
			_place(gate, cp, 0.0, -3.4)
		var n := MeshInstance3D.new()
		n.mesh = torus
		n.material_override = _mat(Color("ffffff"), 0.3, 0.9)
		_place(n, cp, 0.0, 1.0)
		n.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		_rings.append(n)

	# Finish arch.
	var arch := Node3D.new()
	var grand: bool = world < 2 and Props.has("temple_ruins")
	if grand:
		arch.add_child(Props.make("temple_ruins", "Tall_Stone_Archway", 13.5, 0, Color.WHITE if world == 0 else Color(1.55, 1.02, 0.62)))
		arch.get_child(0).position.y = -6.0
	for side in ([] if grand else [-1.0, 1.0]):
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
	var flag := Image.create(24, 4, false, Image.FORMAT_RGBA8)
	for fy in 4:
		for fx in 24:
			flag.set_pixel(fx, fy, Color("f5f5f5") if (fx + fy) % 2 == 0 else Color("15181f"))
	var flag_mat := StandardMaterial3D.new()
	flag_mat.albedo_texture = ImageTexture.create_from_image(flag)
	flag_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	flag_mat.uv1_scale = Vector3(3, 2, 1)
	flag_mat.roughness = 0.7
	banner.material_override = flag_mat
	banner.position.y = 6.4 if grand else 4.6
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

const KIT := "temple_ruins"
const ROCKS_TALL := ["Tall_RockA", "Tall_RockB", "Tall_RockC", "Tall_RockD", "Tall_RockE", "Tall_RockF"]
const ROCKS_SMALL := ["Small_RockA", "Small_RockB", "Small_RockC", "Small_RockD", "Small_RockE", "Small_RockF"]
const TREES := ["TreeA", "TreeB", "TreeC", "TreeD"]
const RUINS := ["Stone_Pillar", "Stone_Pillar_Broken", "Stone_Pillar_Very_Broken", "Stone_Decorative_Pillar",
	"Stone_Decorative_Pillar_Broken", "Stone_Pillar_Tall_Broken", "Stone_Pillar", "Stone_Decorative_Pillar"]
const DESERT_BITS := ["Pilar1_L", "Pilar2_L", "Pilar3_L_001", "Pilar4_L_001", "Pilar5_L_001"]
const MOSS := Color(0.62, 1.25, 0.5)
const SAND := Color(1.55, 1.02, 0.62)

func _pick(rng: RandomNumberGenerator, list: Array) -> String:
	return list[rng.randi() % list.size()]

## Stands a model piece in [parent]; returns it so the caller can stretch or turn it further.
func _stand(parent: Node3D, kit: String, piece: String, at: Vector3, target: float, axis: int = 1, tint: Color = Color.WHITE, turn: float = 0.0, skip: String = "") -> Node3D:
	var n := Props.make(kit, piece, target, axis, tint, false, skip)
	n.position = at
	n.rotation.y = turn
	parent.add_child(n)
	return n

## Road edges of a row in across-road metres: [left, right]; an empty row gives the full width.
func _edges(row: int) -> Vector2:
	var first := -1
	var last := -1
	for c in B.COLS:
		if track.cell(row, c) != Track.Cell.NONE:
			if first < 0:
				first = c
			last = c
	if first < 0:
		return Vector2(-B.COLS * 0.5, B.COLS * 0.5) * B.CELL
	return Vector2(Track.d_of(first) - B.CELL * 0.5, Track.d_of(last) + B.CELL * 0.5)

func _solid_span(from: int, to: int) -> bool:
	for r in range(from, to + 1):
		if r >= track.rows or track.row_empty(r):
			return false
	return true

## A floating island: rock hanging below, a mossy cap, trees and what is left of a temple.
func _island(n: Node3D, rng: RandomNumberGenerator, r: float) -> void:
	var under := _stand(n, KIT, _pick(rng, ROCKS_TALL), Vector3(0, 0.2 * r, 0), r * 2.4, 1, Color.WHITE, rng.randf() * TAU)
	under.rotation.x = PI
	under.scale = Vector3(1.9, 1.0, 1.9)
	var cap := _stand(n, KIT, _pick(rng, ROCKS_SMALL), Vector3(0, -0.12 * r, 0), r * 2.25, 0, MOSS, rng.randf() * TAU)
	cap.scale = Vector3(1.0, 0.3, 1.0)
	var top := 0.12 * r
	for k in rng.randi_range(1, 3):
		var a := rng.randf() * TAU
		var at := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.1, 0.55) * r + Vector3(0, top, 0)
		_stand(n, KIT, _pick(rng, TREES), at, rng.randf_range(5.0, 9.0), 1, Color.WHITE, rng.randf() * TAU)
	for k in rng.randi_range(1, 3):
		var a := rng.randf() * TAU
		var at := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.2, 0.7) * r + Vector3(0, top, 0)
		_stand(n, KIT, _pick(rng, RUINS), at, rng.randf_range(2.4, 5.5), 1, Color.WHITE, rng.randf() * TAU)
	if r > 7.0 and rng.randf() < 0.6:
		_stand(n, KIT, "Stone_Archway" if rng.randf() < 0.5 else "Stone_Archway_Broken", Vector3(0, top, 0), r * 0.7, 1, Color.WHITE, rng.randf() * TAU)

func _glow(node: Node3D, energy: float) -> void:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var src := (mi as MeshInstance3D).mesh.surface_get_material(0) as BaseMaterial3D
		if src == null:
			continue
		var m := src.duplicate() as BaseMaterial3D
		m.emission_enabled = true
		m.emission_texture = m.albedo_texture
		m.emission = Color.WHITE
		m.emission_energy_multiplier = energy
		(mi as MeshInstance3D).material_override = m

func _build_scenery(world_index: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(track.id) + 17
	Props.cutout(KIT)
	Props.two_sided("neon_signs")
	var cube := BoxMesh.new()
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
	var signs: Array = Props.names("neon_signs")

	# Things scattered to both sides of the road.
	var row := 2
	while row < track.rows:
		for side in [-1.0, 1.0]:
			if rng.randf() < 0.15:
				continue
			var n := Node3D.new()
			add_child(n)
			n.rotation.y = rng.randf() * TAU
			match world_index:
				0:
					var r := rng.randf_range(4.5, 10.0)
					n.position = track.to_world(row, side * (rng.randf_range(9.0, 40.0) + r), rng.randf_range(-11.0, 1.5))
					_island(n, rng, r)
				1:
					# A mesa: a tower of sandstone rising from the canyon floor, ruins on the nearer ones.
					var h := rng.randf_range(42.0, 78.0)
					var off: float = rng.randf_range(15.0, 55.0)
					var top := rng.randf_range(-6.0, 9.0)
					n.position = track.to_world(row, side * off, top - h)
					var rock := _stand(n, KIT, _pick(rng, ROCKS_TALL), Vector3.ZERO, h, 1, SAND)
					rock.scale = Vector3(1.0, 1.0, 1.0) * rng.randf_range(1.0, 1.5)
					rock.scale.y = 1.0
					if off < 34.0 and top < 4.0:
						for k in rng.randi_range(1, 3):
							var a := rng.randf() * TAU
							_stand(n, "desert_ruins", _pick(rng, DESERT_BITS), Vector3(cos(a) * 2.2, h - 1.2, sin(a) * 2.2), rng.randf_range(3.5, 7.0), 1, Color.WHITE, rng.randf() * TAU)
				_:
					var h2 := rng.randf_range(34.0, 95.0)
					var w := rng.randf_range(5.0, 9.5)
					n.position = track.to_world(row, side * rng.randf_range(16.0, 46.0), rng.randf_range(2.0, 22.0) - h2 * 0.5)
					n.rotation.y = track.yaw_at(row) + (0.0 if rng.randf() < 0.5 else PI * 0.5)
					_prop(n, cube, lit[rng.randi() % lit.size()], Vector3.ZERO, Vector3(w, h2, w))
					_prop(n, cube, dark, Vector3(0, h2 * 0.5 + 0.6, 0), Vector3(w * 0.7, 1.2, w * 0.7))
					_prop(n, cube, neon_a if rng.randf() < 0.5 else neon_b, Vector3(0, h2 * 0.5 + 0.05, 0), Vector3(w + 0.25, 0.3, w + 0.25))
		row += rng.randi_range(9, 15)

	# Landmarks stand ahead of the player, near the line of sight: a phone held upright sees
	# little to the sides. The last one waits beyond the finish.
	var marks := 0
	var mrow := 70
	var last := false
	while not last and marks < 4:
		last = mrow >= track.rows
		var side := 1.0 if marks % 2 == 0 else -1.0
		var at_row: float = minf(mrow, track.rows - 1)
		var beyond: Vector3 = Track.forward(track.yaw_at(at_row)) * (60.0 if last else 0.0)
		var face: float = track.yaw_at(at_row)
		match world_index:
			0:
				_stand(self, "floating_castle", "*", track.to_world(at_row, side * 44.0, -14.0) + beyond, 64.0, 0, Color.WHITE, face + side * 0.9, "Cloud|Outside")
				var sea := _stand(self, "floating_castle", "CloudsFlat_003", track.to_world(at_row, 0.0, -34.0), 300.0, 0)
				sea.scale = Vector3(1.0, 0.28, 1.0)
			1:
				_stand(self, "desert_ruins", "*", track.to_world(at_row, side * 34.0, -15.0) + beyond, 44.0, 0, Color.WHITE, face + side * 0.6)
			_:
				_stand(self, "cyber_city", "*", track.to_world(at_row, side * 95.0, -26.0) + beyond, 150.0, 0, Color.WHITE, face + marks * 1.57)
		marks += 1
		mrow += 130

	# Beside the road: pillars rising out of the deep with a light on top (signs in the city).
	var prow := 6
	var flip := false
	while prow < track.rows - 4:
		if _solid_span(prow, prow + 1):
			var e := _edges(prow)
			for side in [-1.0, 1.0]:
				var d: float = (e.x - 0.95) if side < 0.0 else (e.y + 0.95)
				var yaw: float = track.yaw_at(prow)
				if world_index == 2:
					if flip == (side > 0.0) and not signs.is_empty():
						var pole := Node3D.new()
						add_child(pole)
						pole.position = track.to_world(prow, d + side * 1.2, 0.0)
						pole.rotation.y = yaw
						_prop(pole, cube, dark, Vector3(0, -6.0, 0), Vector3(0.25, 22.0, 0.25))
						_stand(pole, "neon_signs", _pick(rng, signs), Vector3(0, 2.2, 0), 2.1, 0)
				else:
					var tint: Color = Color.WHITE if world_index == 0 else SAND
					var post := _stand(self, KIT, "Stone_Pillar_Tall", track.to_world(prow, d, -17.7), 18.0, 1, tint, yaw)
					post.scale = Vector3(0.5, 1.0, 0.5)
					if flip == (side > 0.0):
						var gem := _stand(self, "crystal", "*", track.to_world(prow, d, 0.3), 1.1, 1, Color.WHITE, rng.randf() * TAU)
						_glow(gem, 0.75)
		prow += 11
		flip = not flip

	# Under the road: arches of a bridge, so it rests on something.
	var r2 := 3
	while r2 < track.rows - 2:
		if _solid_span(r2, r2 + 5):
			var e := _edges(r2 + 2)
			var k := Node3D.new()
			add_child(k)
			k.position = track.to_world(r2 + 3.0, (e.x + e.y) * 0.5, -TILE_DEPTH + 0.02)
			k.rotation.y = track.yaw_at(r2 + 3.0)
			if world_index == 2:
				var wide: float = e.y - e.x
				_prop(k, cube, dark, Vector3(0, -0.5, 0), Vector3(wide * 0.6, 1.0, 6.0))
				_prop(k, cube, neon_a, Vector3(0, -1.05, 0), Vector3(wide * 0.62, 0.12, 6.0))
			else:
				var s := Props.size(KIT, "Stone_Bridge_Arch")
				var arch := Props.make(KIT, "Stone_Bridge_Arch", 1.0, 1, Color.WHITE if world_index == 0 else SAND)
				# Modelled lengthwise along x: turn it along the road, then fit it to this stretch.
				arch.rotation.y = PI * 0.5
				arch.scale = Vector3(6.3 / (s.x / s.y), 7.5, (e.y - e.x + 0.5) / (s.z / s.y))
				arch.position.y = -7.5
				k.add_child(arch)
			_keels.append([r2, k])
		r2 += 6

	if world_index == 1:
		# The canyon floor, far below.
		var floor := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(3000, 3000)
		floor.mesh = pm
		floor.material_override = _mat(Color("b8683a"), 1.0)
		floor.position = track.to_world(track.rows * 0.5, 0.0, 0.0) + Vector3(0, -62.0, 0)
		add_child(floor)

func _build_ball(skin: String) -> void:
	ball = Skins.build(skin)
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
	var at := ball.position
	ball.queue_free()
	ball = Skins.build(skin)
	add_child(ball)
	ball.position = at
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
