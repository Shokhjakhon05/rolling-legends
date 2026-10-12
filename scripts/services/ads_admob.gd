## The AdMob side of AdsService (Poing Studios plugin). Loaded only on Android. Asks for
## consent where the law wants it, then keeps one rewarded and one interstitial ad loaded.
extends Node

const Config := preload("res://scripts/services/ads_config.gd")

var _rewarded: RewardedAd
var _interstitial: InterstitialAd
var _rewarded_loader := RewardedAdLoader.new()
var _interstitial_loader := InterstitialAdLoader.new()
var _started := false
var _retry := 0

func _ready() -> void:
	_request_consent()

func _request_consent() -> void:
	var info := UserMessagingPlatform.consent_information
	info.update(
		ConsentRequestParameters.new(),
		func() -> void:
			if info.get_is_consent_form_available() and info.get_consent_status() == ConsentInformation.ConsentStatus.REQUIRED:
				UserMessagingPlatform.load_consent_form(
					func(form: ConsentForm) -> void:
						form.show(func(_error: FormError) -> void: _start()),
					func(_error: FormError) -> void: _start())
			else:
				_start(),
		func(_error: FormError) -> void: _start())

func _start() -> void:
	if _started:
		return
	_started = true
	var on_init := OnInitializationCompleteListener.new()
	on_init.on_initialization_complete = func(_status: InitializationStatus) -> void:
		_load_rewarded()
		_load_interstitial()
	MobileAds.set_request_configuration(RequestConfiguration.new())
	MobileAds.initialize(on_init)

## A failed load is tried again later, more and more rarely: no network must not mean a
## request every second.
func _later(what: Callable) -> void:
	_retry = mini(_retry + 1, 6)
	get_tree().create_timer(15.0 * _retry).timeout.connect(what)

func _load_rewarded() -> void:
	var callback := RewardedAdLoadCallback.new()
	callback.on_ad_loaded = func(ad: RewardedAd) -> void:
		_rewarded = ad
		_retry = 0
	callback.on_ad_failed_to_load = func(_error: LoadAdError) -> void:
		_later(_load_rewarded)
	_rewarded_loader.load(Config.rewarded_id(), AdRequest.new(), callback)

func _load_interstitial() -> void:
	var callback := InterstitialAdLoadCallback.new()
	callback.on_ad_loaded = func(ad: InterstitialAd) -> void:
		_interstitial = ad
		_retry = 0
	callback.on_ad_failed_to_load = func(_error: LoadAdError) -> void:
		_later(_load_interstitial)
	_interstitial_loader.load(Config.interstitial_id(), AdRequest.new(), callback)

func rewarded_ready() -> bool:
	return _rewarded != null

func interstitial_ready() -> bool:
	return _interstitial != null

func show_rewarded(done: Callable) -> void:
	var ad := _rewarded
	_rewarded = null
	var state := {"earned": false, "closed": false}
	var finish := func() -> void:
		if state["closed"]:
			return
		state["closed"] = true
		ad.destroy()
		_load_rewarded()
		done.call(state["earned"])
	var content := FullScreenContentCallback.new()
	content.on_ad_dismissed_full_screen_content = finish
	content.on_ad_failed_to_show_full_screen_content = func(_error: AdError) -> void:
		finish.call()
	ad.full_screen_content_callback = content
	var reward := OnUserEarnedRewardListener.new()
	reward.on_user_earned_reward = func(_item: RewardedItem) -> void:
		state["earned"] = true
	ad.show(reward)

func show_interstitial(done: Callable) -> void:
	var ad := _interstitial
	_interstitial = null
	var state := {"closed": false}
	var finish := func() -> void:
		if state["closed"]:
			return
		state["closed"] = true
		ad.destroy()
		_load_interstitial()
		done.call()
	var content := FullScreenContentCallback.new()
	content.on_ad_dismissed_full_screen_content = finish
	content.on_ad_failed_to_show_full_screen_content = func(_error: AdError) -> void:
		finish.call()
	ad.full_screen_content_callback = content
	ad.show()

func privacy_options_available() -> bool:
	var info := UserMessagingPlatform.consent_information
	return info.get_privacy_options_requirement_status() == ConsentInformation.PrivacyOptionsRequirementStatus.REQUIRED

func show_privacy_options() -> void:
	UserMessagingPlatform.show_privacy_options_form(func(_error: FormError) -> void: pass)
