## The only place the game talks to the ad SDK. Without the SDK (desktop, tests, a failed
## start) every call quietly answers "no ad": the game never waits for an ad to go on.
extends Node

const Config := preload("res://scripts/services/ads_config.gd")

var _impl: Node = null
var _levels_since := 0
var _last_interstitial := -1e9
var _last_rewarded := -1e9

func _ready() -> void:
	if OS.get_name() == "Android" and ResourceLoader.exists("res://scripts/services/ads_admob.gd"):
		var script = load("res://scripts/services/ads_admob.gd")
		if script != null:
			_impl = script.new()
			add_child(_impl)

func rewarded_ready() -> bool:
	return _impl != null and _impl.rewarded_ready()

## Shows a rewarded ad. [done] is called exactly once, with true only when the SDK confirmed
## that the reward was earned.
func show_rewarded(done: Callable) -> void:
	if not rewarded_ready():
		done.call(false)
		return
	_last_rewarded = _now()
	_impl.show_rewarded(done)

## Called when a level is finished: decides whether an interstitial is due.
func note_level_finished() -> void:
	_levels_since += 1

func interstitial_due(levels_done: int) -> bool:
	if levels_done <= Config.NO_INTERSTITIAL_BEFORE_LEVELS:
		return false
	if _levels_since < Config.INTERSTITIAL_EVERY_LEVELS:
		return false
	if _now() - _last_interstitial < Config.INTERSTITIAL_COOLDOWN_SEC:
		return false
	if _now() - _last_rewarded < Config.AFTER_REWARDED_SEC:
		return false
	return true

## Shows an interstitial if one is due and loaded; [done] is called when the game may go on.
func maybe_interstitial(levels_done: int, done: Callable) -> void:
	if _impl == null or not interstitial_due(levels_done) or not _impl.interstitial_ready():
		done.call()
		return
	_levels_since = 0
	_last_interstitial = _now()
	_impl.show_interstitial(done)

func privacy_options_available() -> bool:
	return _impl != null and _impl.privacy_options_available()

func show_privacy_options() -> void:
	if _impl != null:
		_impl.show_privacy_options()

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
