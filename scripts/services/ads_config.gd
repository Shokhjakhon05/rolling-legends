## Ad unit ids. The values in source control are Google's public test ids; a release build
## gets the real ones written into project.godot by CI from repository secrets
## (admob/units/rewarded, admob/units/interstitial, admob/general/android/app_id).
extends RefCounted

const TEST_REWARDED := "ca-app-pub-3940256099942544/5224354917"
const TEST_INTERSTITIAL := "ca-app-pub-3940256099942544/1033173712"

const NO_INTERSTITIAL_BEFORE_LEVELS := 3   # finished levels before the first interstitial
const INTERSTITIAL_EVERY_LEVELS := 2
const INTERSTITIAL_COOLDOWN_SEC := 90.0
const AFTER_REWARDED_SEC := 60.0

static func rewarded_id() -> String:
	return str(ProjectSettings.get_setting("admob/units/rewarded", TEST_REWARDED))

static func interstitial_id() -> String:
	return str(ProjectSettings.get_setting("admob/units/interstitial", TEST_INTERSTITIAL))
