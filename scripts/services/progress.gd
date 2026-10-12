## The player's saved progress and settings. One JSON file in user://; a damaged or missing
## file simply means a fresh start.
extends Node

signal changed

const PATH := "user://save.json"
const VERSION := 1

const SKINS := [
	{"id": "legend", "price": 0},
	{"id": "classic", "price": 0},
	{"id": "neon_pulse", "price": 0, "need_level": 10},
	{"id": "gold_core", "price": 150},
	{"id": "lava", "price": 350},
	{"id": "retro_pixel", "price": 0, "need_stars": 45},
	{"id": "storm", "price": 600},
]

var stars := {}            # level number (as text) -> best stars
var best_time := {}        # level number (as text) -> best time, seconds
var crystals := 0          # wallet
var owned: Array = ["legend", "classic"]
var skin := "legend"
var sound := true
var music := true
var vibration := true
var sensitivity := 1.0
var language := ""
var levels_done := 0       # finished levels since install, for ad pacing
var tutorial_done := false
var persist := true        # tests switch saving off

func _ready() -> void:
	load_save()

func load_save() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary):
		return
	stars = _dict(data.get("stars"))
	best_time = _dict(data.get("best_time"))
	crystals = maxi(int(data.get("crystals", 0)), 0)
	var o = data.get("owned")
	owned = o if o is Array and not o.is_empty() else ["classic"]
	if not owned.has("classic"):
		owned.append("classic")
	skin = str(data.get("skin", "legend"))
	# The hero ball arrived in 0.3: everyone gets it, and it is put on once.
	if not owned.has("legend"):
		owned.append("legend")
		skin = "legend"
	if not owned.has(skin):
		skin = "legend"
	sound = bool(data.get("sound", true))
	music = bool(data.get("music", true))
	vibration = bool(data.get("vibration", true))
	sensitivity = clampf(float(data.get("sensitivity", 1.0)), 0.5, 2.0)
	language = str(data.get("language", ""))
	levels_done = int(data.get("levels_done", 0))
	tutorial_done = bool(data.get("tutorial_done", false))

func _dict(v) -> Dictionary:
	return v if v is Dictionary else {}

func save() -> void:
	changed.emit()
	if not persist:
		return
	var data := {
		"version": VERSION, "stars": stars, "best_time": best_time, "crystals": crystals,
		"owned": owned, "skin": skin, "sound": sound, "music": music, "vibration": vibration,
		"sensitivity": sensitivity, "language": language, "levels_done": levels_done,
		"tutorial_done": tutorial_done,
	}
	# Written to a temporary file first: a kill mid-write must not cost the save.
	var f := FileAccess.open(PATH + ".tmp", FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data))
	f.close()
	DirAccess.rename_absolute(PATH + ".tmp", PATH)

func stars_of(level: int) -> int:
	return int(stars.get(str(level), 0))

func total_stars() -> int:
	var n := 0
	for k in stars:
		n += int(stars[k])
	return n

## Levels are 1-based. A level opens when the one before it has been finished.
func unlocked(level: int) -> bool:
	return level <= 1 or stars_of(level - 1) > 0

func next_level(total: int) -> int:
	for i in range(1, total + 1):
		if stars_of(i) == 0:
			return i
	return total

## Banks a finished level. Returns what changed, for the result screen.
func finish_level(level: int, got_stars: int, time: float, collected: int) -> Dictionary:
	var key := str(level)
	var before := stars_of(level)
	var first := before == 0
	if got_stars > before:
		stars[key] = got_stars
	var record := not best_time.has(key) or time < float(best_time[key])
	if record:
		best_time[key] = snappedf(time, 0.01)
	var reward := collected + (10 if first else 0)
	crystals += reward
	levels_done += 1
	var unlocked_skins := grant_skins()
	save()
	return {"first": first, "record": record, "reward": reward, "new_stars": maxi(got_stars - before, 0), "skins": unlocked_skins}

func add_crystals(n: int) -> void:
	crystals += maxi(n, 0)
	save()

func skin_state(id: String) -> String:
	if owned.has(id):
		return "owned"
	for s in SKINS:
		if s["id"] == id:
			if s.has("need_level") or s.has("need_stars"):
				return "locked"
			return "buy"
	return "locked"

## Skins that are prizes rather than purchases are handed over as soon as they are earned.
func grant_skins() -> Array:
	var out := []
	for s in SKINS:
		if owned.has(s["id"]):
			continue
		if s.has("need_level") and stars_of(int(s["need_level"])) > 0:
			owned.append(s["id"])
			out.append(s["id"])
		elif s.has("need_stars") and total_stars() >= int(s["need_stars"]):
			owned.append(s["id"])
			out.append(s["id"])
	return out

func buy_skin(id: String) -> bool:
	for s in SKINS:
		if s["id"] == id and skin_state(id) == "buy" and crystals >= int(s["price"]):
			crystals -= int(s["price"])
			owned.append(id)
			skin = id
			save()
			return true
	return false

func select_skin(id: String) -> void:
	if owned.has(id):
		skin = id
		save()
