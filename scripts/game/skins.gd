## Ball skins: purely visual. Every ball has the same radius, mass and grip.
## A skin is a small model, not a paint job: build() returns the body plus whatever rings,
## studs, shells and cores make that ball its own design.
extends RefCounted

const HERO_MODEL := "res://assets/models/hero_ball.glb"

const INFO := {
	"legend": {"a": Color("0a1626"), "b": Color("18b8ff"), "metal": 0.5, "rough": 0.22, "glow": 0.0},
	"classic": {"a": Color("aeb9c8"), "b": Color("1668f0"), "metal": 0.85, "rough": 0.22, "glow": 0.0},
	"neon_pulse": {"a": Color("131a30"), "b": Color("22e6ff"), "metal": 0.6, "rough": 0.35, "glow": 1.6},
	"gold_core": {"a": Color("f5b82e"), "b": Color("5a3410"), "metal": 0.95, "rough": 0.22, "glow": 0.0},
	"lava": {"a": Color("2a1410"), "b": Color("ff7a1a"), "metal": 0.1, "rough": 0.8, "glow": 2.0},
	"retro_pixel": {"a": Color("3b2e7e"), "b": Color("ffd23f"), "metal": 0.0, "rough": 0.9, "glow": 0.0},
	"storm": {"a": Color("08090f"), "b": Color("38e8ff"), "metal": 0.7, "rough": 0.07, "glow": 1.1},
}

static var _cache := {}

static func colors(id: String) -> Dictionary:
	return INFO.get(id, INFO["classic"])

static func material(id: String) -> StandardMaterial3D:
	if _cache.has(id):
		return _cache[id]
	var info: Dictionary = colors(id)
	var size := Vector2i(256, 128)
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var glow := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(info["a"])
	glow.fill(Color.BLACK)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	match id:
		"classic":
			_band(img, 52, 76, info["b"])
			_band(img, 40, 44, Color("ffffff"))
			_band(img, 84, 88, Color("ffffff"))
			for x in range(0, size.x, 64):  # marks along the band so the roll is visible
				img.fill_rect(Rect2i(x, 58, 20, 12), Color("ffffff"))
		"neon_pulse":
			for y in [24, 64, 104]:
				_band(img, y - 3, y + 3, info["b"])
				_band(glow, y - 3, y + 3, info["b"])
			for x in range(0, size.x, 32):
				img.fill_rect(Rect2i(x, 0, 5, size.y), info["b"])
				glow.fill_rect(Rect2i(x, 0, 5, size.y), info["b"])
		"gold_core":
			_band(img, 30, 44, info["b"])
			_band(img, 84, 98, info["b"])
			for x in range(0, size.x, 32):
				img.fill_rect(Rect2i(x, 56, 16, 16), Color("fff1b0"))
		"lava":
			for k in 26:
				var p := Vector2(rng.randf() * size.x, rng.randf() * size.y)
				for step in 30:
					p += Vector2(rng.randf_range(-4, 4), rng.randf_range(-4, 4))
					var r := Rect2i(int(posmod(int(p.x), size.x)), clampi(int(p.y), 0, size.y - 4), 4, 4)
					img.fill_rect(r, info["b"])
					glow.fill_rect(r, info["b"])
		"retro_pixel":
			var palette := [Color("ff5d73"), Color("ffd23f"), Color("3ddc97"), Color("4ea8ff"), Color("f5f5f5"), info["a"], info["a"]]
			for y in range(0, size.y, 16):
				for x in range(0, size.x, 16):
					img.fill_rect(Rect2i(x, y, 16, 16), palette[rng.randi() % palette.size()])
		"storm":
			# Thin right-angled traces, like circuitry under black glass.
			for k in 14:
				var x := int(rng.randf() * size.x)
				var y := int(rng.randf_range(10, size.y - 10))
				for leg in rng.randi_range(2, 4):
					var run := rng.randi_range(10, 36)
					if leg % 2 == 0:
						glow.fill_rect(Rect2i(x, y, run, 2), info["b"])
						x = posmod(x + run, size.x - 40)
					else:
						run = rng.randi_range(6, 18) * (1 if rng.randf() < 0.5 else -1)
						glow.fill_rect(Rect2i(x, mini(y, y + run), 2, absi(run)), info["b"])
						y = clampi(y + run, 8, size.y - 8)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.metallic = info["metal"]
	m.roughness = info["rough"]
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST if id == "retro_pixel" else BaseMaterial3D.TEXTURE_FILTER_LINEAR
	# A lacquered, lit-from-behind look: what makes a ball read as an object worth owning.
	m.clearcoat_enabled = true
	m.clearcoat = 0.8
	m.clearcoat_roughness = 0.12
	# Dark balls must stay dark: a mirror finish would only show the bright sky.
	var dark: bool = (info["a"] as Color).get_luminance() < 0.2
	m.metallic_specular = 0.25 if dark else 0.5
	if dark:
		m.metallic = minf(m.metallic, 0.3)
		m.roughness = maxf(m.roughness, 0.22)
		m.clearcoat = 0.35
	if info["glow"] > 0.0:
		m.emission_enabled = true
		m.emission_texture = ImageTexture.create_from_image(glow)
		m.emission = Color.WHITE
		m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY   # the texture says where it glows
		m.emission_energy_multiplier = info["glow"]
	_cache[id] = m
	return m

static func _band(img: Image, y0: int, y1: int, c: Color) -> void:
	img.fill_rect(Rect2i(0, y0, img.get_width(), y1 - y0), c)

const R := 0.5

static func _plain(color: Color, metal: float, rough: float, glow: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metal
	m.roughness = rough
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m

static func _sphere(parent: Node3D, radius: float, mat: Material, at: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 32 if radius > 0.3 else 12
	mesh.rings = 16 if radius > 0.3 else 6
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = mat
	n.position = at
	parent.add_child(n)
	return n

## A band around the ball. [axis] is the direction the ring's hole faces.
static func _ring(parent: Node3D, inner: float, outer: float, mat: Material, axis: Vector3) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 40
	mesh.ring_segments = 10
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = mat
	if not axis.is_equal_approx(Vector3.UP):
		n.basis = Basis(Quaternion(Vector3.UP, axis.normalized()))
	parent.add_child(n)
	return n

## The owner's hero ball, modelled in Higgsfield 3D Jutsu. The file is a whole preview scene:
## the floor, pedestal, camera and lights are dropped, and the ball is scaled so that its body
## has the game's radius.
static func _hero() -> Node3D:
	if not ResourceLoader.exists(HERO_MODEL):
		return null
	var scene: PackedScene = load(HERO_MODEL)
	if scene == null:
		return null
	var model: Node3D = scene.instantiate()
	var body: MeshInstance3D = null
	for n in model.find_children("*", "", true, false):
		var name := String(n.name)
		if name.begins_with("PREVIEW") or name.begins_with("CAM") or name.begins_with("LGT") or n is Light3D or n is Camera3D:
			n.get_parent().remove_child(n)
			n.queue_free()
		elif n is MeshInstance3D:
			if name.begins_with("HERO"):
				body = n
			_tame(n)
	if body == null:
		model.queue_free()
		return null
	# Centre on the body and bring it to the game's radius.
	var box: AABB = body.get_aabb()
	var to_root := body.transform
	var p: Node = body.get_parent()
	while p != null and p != model:
		to_root = (p as Node3D).transform * to_root
		p = p.get_parent()
	var centre: Vector3 = to_root * box.get_center()
	var radius: float = (to_root.basis * box.size).length() / sqrt(3.0) * 0.5
	var k := R / maxf(radius, 0.001)
	var holder := Node3D.new()
	holder.add_child(model)
	model.position = -centre * k
	model.scale = Vector3.ONE * k
	return holder

## Mirror-dark metal only shows the bright sky; keep the model's colours as its author saw them.
static func _tame(mesh: MeshInstance3D) -> void:
	for i in mesh.mesh.get_surface_count():
		var src := mesh.mesh.surface_get_material(i)
		if src is StandardMaterial3D:
			var m: StandardMaterial3D = src.duplicate()
			if m.albedo_color.get_luminance() < 0.2:
				m.metallic = minf(m.metallic, 0.35)
				m.metallic_specular = 0.3
				m.clearcoat_enabled = true
				m.clearcoat = 0.5
				m.clearcoat_roughness = 0.1
			if m.emission_enabled:
				m.emission_energy_multiplier = minf(m.emission_energy_multiplier, 1.3)
			mesh.set_surface_override_material(i, m)

## The whole ball as a node; rotate it and everything rolls together.
static func build(id: String) -> Node3D:
	var root := Node3D.new()
	if id == "legend":
		var hero := _hero()
		if hero != null:
			root.add_child(hero)
			return root
	match id:
		"gold_core":      # Solar Gold: polished gold, bronze hoops, bright studs at the poles
			# Not a pure mirror: under a blue sky mirrored gold turns green.
			var gold := _plain(Color("ffa91a"), 0.55, 0.24, 0.22)
			gold.metallic_specular = 0.45
			gold.clearcoat_enabled = true
			gold.clearcoat = 0.5
			_sphere(root, R * 0.97, gold)
			var bronze := _plain(Color("6a3a10"), 0.3, 0.45)
			for axis in [Vector3.UP, Vector3.RIGHT, Vector3.BACK]:
				_ring(root, R * 0.9, R * 1.0, bronze, axis)
			var stud := _plain(Color("fff2b8"), 1.0, 0.1, 0.5)
			for dir in [Vector3(1, 1, 1), Vector3(-1, 1, 1), Vector3(1, -1, 1), Vector3(1, 1, -1), Vector3(-1, -1, 1), Vector3(-1, 1, -1), Vector3(1, -1, -1), Vector3(-1, -1, -1)]:
				_sphere(root, 0.075, stud, dir.normalized() * R * 0.93)
		"neon_pulse":     # Neon Reactor: a burning core inside a dark glass shell and a cage
			_sphere(root, R * 0.5, _plain(Color("12d6ff"), 0.0, 0.4, 1.15))
			var glass := _plain(Color(0.03, 0.05, 0.16, 0.55), 0.2, 0.15)
			glass.metallic_specular = 0.3
			glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			glass.cull_mode = BaseMaterial3D.CULL_BACK
			_sphere(root, R * 0.98, glass)
			var cage := _plain(Color("141a30"), 0.3, 0.4)
			_ring(root, R * 0.9, R * 1.0, cage, Vector3.RIGHT)
			_ring(root, R * 0.9, R * 1.0, cage, Vector3.BACK)
			_ring(root, R * 0.94, R * 1.0, _plain(Color("ff2fe0"), 0.0, 0.4, 1.3), Vector3.UP)
			for side in [1.0, -1.0]:
				_sphere(root, 0.09, _plain(Color("12d6ff"), 0.0, 0.3, 1.2), Vector3(0, side * R * 0.95, 0))
		"storm":          # Obsidian Core: black glass with thin cyan seams
			var body := material("storm")
			_sphere(root, R * 0.985, body)
			var seam := _plain(Color("18d8ff"), 0.0, 0.3, 1.25)
			_ring(root, R * 0.975, R * 1.0, seam, Vector3(1, 0.35, 0))
			_ring(root, R * 0.975, R * 1.0, seam, Vector3(-0.35, 1, 0.5))
			var cap := _plain(Color("20242f"), 0.3, 0.35)
			for side in [1.0, -1.0]:
				_sphere(root, 0.13, cap, Vector3(side * R * 0.9, side * R * 0.32, 0).normalized() * R * 0.93)
		_:
			_sphere(root, R, material(id))
	return root
