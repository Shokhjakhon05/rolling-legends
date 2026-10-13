## Hand-made models (credits: assets/models/world/CREDITS.md) cut into pieces that can be stood
## anywhere. A piece is everything under one named node of a model; "*" is the whole model.
extends RefCounted

const DIR := "res://assets/models/world/"

static var _kits := {}     # kit -> {piece -> Array of [Mesh, Transform3D]}
static var _tinted := {}   # [material id, tint] -> Material

static func has(kit: String) -> bool:
	return not _pieces(kit).is_empty()

static func names(kit: String) -> Array:
	return _pieces(kit).keys()

static func _pieces(kit: String) -> Dictionary:
	if _kits.has(kit):
		return _kits[kit]
	var pieces := {}
	var path := DIR + kit + ".glb"
	if ResourceLoader.exists(path):
		var root: Node = (load(path) as PackedScene).instantiate()
		_collect(root, Transform3D.IDENTITY, pieces)
		root.free()
	_kits[kit] = pieces
	return pieces

static func _collect(n: Node, xf: Transform3D, pieces: Dictionary) -> void:
	var here := xf
	if n is Node3D:
		here = xf * (n as Node3D).transform
	if n is MeshInstance3D:
		var key := str(n.get_parent().name)
		if not pieces.has(key):
			pieces[key] = []
		pieces[key].append([(n as MeshInstance3D).mesh, here])
	for c in n.get_children():
		_collect(c, here, pieces)

static func _parts(kit: String, piece: String, skip: String) -> Array:
	var pieces := _pieces(kit)
	if piece != "*":
		return pieces.get(piece, [])
	var all := []
	for key in pieces:
		var wanted := true
		for word in skip.split("|", false):
			if str(key).contains(word):
				wanted = false
		if wanted:
			all.append_array(pieces[key])
	return all

static func _bounds(parts: Array) -> AABB:
	var box := AABB()
	var first := true
	for p in parts:
		var b: AABB = (p[1] as Transform3D) * (p[0] as Mesh).get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box

## Size of a piece as modelled, before any scaling.
static func size(kit: String, piece: String) -> Vector3:
	return _bounds(_parts(kit, piece, "")).size

## A piece standing on the origin (centre of its base), scaled so that its extent along [axis]
## (0 = width, 1 = height, 2 = depth) is [target]. Returns an empty node if the model is missing.
static func make(kit: String, piece: String, target: float, axis: int = 1, tint: Color = Color.WHITE, shadows: bool = false, skip: String = "") -> Node3D:
	var holder := Node3D.new()
	var parts := _parts(kit, piece, skip)
	if parts.is_empty():
		return holder
	var box := _bounds(parts)
	var k: float = target / maxf(box.size[axis], 0.0001)
	var inner := Node3D.new()
	inner.scale = Vector3.ONE * k
	inner.position = -Vector3(box.get_center().x, box.position.y, box.get_center().z) * k
	holder.add_child(inner)
	for p in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = p[0]
		mi.transform = p[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if tint != Color.WHITE:
			for s in mi.mesh.get_surface_count():
				mi.set_surface_override_material(s, _tint(mi.mesh.surface_get_material(s), tint))
		inner.add_child(mi)
	return holder

static func _tint(m: Material, tint: Color) -> Material:
	if not (m is BaseMaterial3D):
		return m
	var key := [m.get_instance_id(), tint]
	if not _tinted.has(key):
		var copy := m.duplicate() as BaseMaterial3D
		copy.albedo_color = Color(copy.albedo_color.r * tint.r, copy.albedo_color.g * tint.g, copy.albedo_color.b * tint.b, copy.albedo_color.a)
		_tinted[key] = copy
	return _tinted[key]

## The first material of a kit whose name contains [name] (to reuse its textures elsewhere).
static func material(kit: String, name: String) -> BaseMaterial3D:
	for key in _pieces(kit):
		for p in _pieces(kit)[key]:
			var mesh := p[0] as Mesh
			for s in mesh.get_surface_count():
				var m := mesh.surface_get_material(s)
				if m is BaseMaterial3D and str(m.resource_name).contains(name):
					return m
	return null

## Leaves and grass are drawn as cut-outs: cheaper than blending and they sort correctly.
static func cutout(kit: String) -> void:
	for m in _materials(kit):
		if m.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			m.alpha_scissor_threshold = 0.4
			m.cull_mode = BaseMaterial3D.CULL_DISABLED

static func two_sided(kit: String) -> void:
	for m in _materials(kit):
		m.cull_mode = BaseMaterial3D.CULL_DISABLED

static func _materials(kit: String) -> Array[BaseMaterial3D]:
	var out: Array[BaseMaterial3D] = []
	for key in _pieces(kit):
		for p in _pieces(kit)[key]:
			var mesh := p[0] as Mesh
			for s in mesh.get_surface_count():
				var m := mesh.surface_get_material(s)
				if m is BaseMaterial3D and not out.has(m):
					out.append(m)
	return out
