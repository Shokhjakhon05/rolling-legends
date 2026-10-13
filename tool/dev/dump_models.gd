## Prints the node tree of the world models: godot --headless -s tool/dev/dump_models.gd
extends SceneTree

func _init() -> void:
	for f in ["temple_ruins", "floating_castle", "desert_ruins", "cyber_city", "neon_signs", "crystal"]:
		var scene: PackedScene = load("res://assets/models/world/%s.glb" % f)
		var root := scene.instantiate()
		print("== ", f)
		_walk(root, Transform3D.IDENTITY, 0, f)
		root.free()
	quit()

func _walk(n: Node, xf: Transform3D, depth: int, f: String) -> void:
	var here := xf
	if n is Node3D:
		here = xf * (n as Node3D).transform
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var box: AABB = here * mi.mesh.get_aabb()
		var m: Material = mi.mesh.surface_get_material(0)
		var info := ""
		if m is BaseMaterial3D:
			var bm := m as BaseMaterial3D
			info = "%s shade%d tr%d em%s col%s" % [bm.resource_name, bm.shading_mode, bm.transparency, bm.emission_enabled, bm.albedo_color.to_html()]
		print("%s%s <%s> size %.1v at %.1v | %s" % ["  ".repeat(mini(depth, 4)), n.name, n.get_parent().name, box.size, box.get_center(), info])
	elif depth < 3:
		print("%s%s" % ["  ".repeat(depth), n.name])
	for c in n.get_children():
		_walk(c, here, depth + 1, f)
