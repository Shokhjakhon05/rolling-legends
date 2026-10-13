## The campaign: which levels exist, in what order, and their data.
extends RefCounted

const Track := preload("res://scripts/core/track.gd")
const DIR := "res://data/levels"
const WORLDS := ["sky_islands", "desert_canyon", "neon_nights"]

static var _cache: Array[Dictionary] = []

## All levels in campaign order. Each entry is the parsed level file.
static func all() -> Array[Dictionary]:
	if not _cache.is_empty():
		return _cache
	var index := _read(DIR + "/index.json")
	for path in index.get("levels", []):
		var data := _read(DIR + "/" + str(path))
		if not data.is_empty():
			_cache.append(data)
	return _cache

## Levels in each world (the campaign is split evenly).
static func per_world() -> int:
	return maxi(count() / WORLDS.size(), 1)

static func count() -> int:
	return all().size()

static func data(i: int) -> Dictionary:
	return all()[i]

static func track(i: int) -> RefCounted:
	return Track.from_data(all()[i])

static func world_index(i: int) -> int:
	return maxi(WORLDS.find(str(all()[i].get("world", ""))), 0)

static func _read(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("cannot read " + path)
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}
