## Ball skins: purely visual. Every ball has the same radius, mass and grip.
extends RefCounted

const INFO := {
	"classic": {"a": Color("c9d2dc"), "b": Color("2f8bff"), "metal": 0.75, "rough": 0.3, "glow": 0.0},
	"neon_pulse": {"a": Color("131a30"), "b": Color("22e6ff"), "metal": 0.6, "rough": 0.35, "glow": 1.6},
	"gold_core": {"a": Color("f2b632"), "b": Color("a86a12"), "metal": 0.95, "rough": 0.22, "glow": 0.0},
	"lava": {"a": Color("2a1410"), "b": Color("ff7a1a"), "metal": 0.1, "rough": 0.8, "glow": 2.0},
	"retro_pixel": {"a": Color("3b2e7e"), "b": Color("ffd23f"), "metal": 0.0, "rough": 0.9, "glow": 0.0},
	"storm": {"a": Color("1a1f5c"), "b": Color("b79bff"), "metal": 0.5, "rough": 0.4, "glow": 1.8},
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
			for k in 9:
				var x := rng.randf() * size.x
				var y := 0.0
				while y < size.y:
					var r := Rect2i(int(posmod(int(x), size.x)), int(y), 5, 9)
					img.fill_rect(r, info["b"])
					glow.fill_rect(r, info["b"])
					x += rng.randf_range(-12, 12)
					y += 8
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.metallic = info["metal"]
	m.roughness = info["rough"]
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST if id == "retro_pixel" else BaseMaterial3D.TEXTURE_FILTER_LINEAR
	if info["glow"] > 0.0:
		m.emission_enabled = true
		m.emission_texture = ImageTexture.create_from_image(glow)
		m.emission = Color.WHITE
		m.emission_energy_multiplier = info["glow"]
	_cache[id] = m
	return m

static func _band(img: Image, y0: int, y1: int, c: Color) -> void:
	img.fill_rect(Rect2i(0, y0, img.get_width(), y1 - y0), c)
