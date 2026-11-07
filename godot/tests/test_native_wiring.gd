extends SceneTree
## Scene-level wiring test with an explicit fake native singleton, not a real SDK test.
var failures := 0
var checks := 0

class NativeMock extends Node:
	signal login_result(id: int, authenticated: bool)
	signal reward_result(id: int, transaction: String)
	signal test_reward_result(id: int, earned: bool, message: String)
	signal test_ad_status(message: String)
	var configured_id := "not-called"
	var requested := -1
	func has_java_method(method: String) -> bool:
		return has_method(method)
	func configure_google_sign_in(value: String) -> void:
		configured_id = value
	func capabilities() -> Dictionary:
		return {"account": false, "rewarded_ads": false, "test_rewarded_ads": true, "privacy_options": true, "label": "FAKE test fixture"}
	func start_login(id: int) -> void:
		login_result.emit(id, false)
	func cancel_login(_id: int) -> void:
		pass
	func logout() -> void:
		pass
	func show_rewarded(id: int, _placement: String) -> void:
		reward_result.emit(id, "")
	func stop_ads() -> void:
		pass
	func is_reward_verified(_id: int, _transaction: String) -> bool:
		return false
	func set_test_eligibility(_adult: bool, _outside: bool, _opted: bool) -> void:
		pass
	func start_test_rewarded(id: int) -> void:
		requested = id
	func show_privacy_options() -> void:
		pass

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var mock := NativeMock.new()
	root.add_child(mock)
	Engine.register_singleton("KiteGoogleServices", mock)
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	check(mock.configured_id == "", "Missing public OAuth config stays empty")
	check(scene.services.get_status().test_ads_available, "Native test capability reaches coordinator")
	check(not scene.services.get_status().account_available and not scene.services.get_status().ads_available, "Unconfigured login and production ads remain unavailable")
	check(not scene.services.request_test_rewarded_ad() and mock.requested == -1, "No request before explicit eligibility/opt-in")
	scene.services.set_age_eligibility("adult")
	scene.services.set_test_ad_opt_in(true)
	check(scene.services.request_test_rewarded_ad() and mock.requested >= 0, "Explicit test request reaches native bridge")
	var wins_before: int = scene.profile.data.wins
	var best_before: int = scene.profile.data.best_score
	mock.test_reward_result.emit(mock.requested, true, "MOCK completion")
	check(scene.hud.toast.contains("Demo only") and scene.profile.data.wins == wins_before and scene.profile.data.best_score == best_before, "Test completion only notifies and never awards saved progress")
	mock.test_ad_status.emit("Native status fixture")
	check(scene.hud.toast == "Native status fixture", "Native status signal reaches visible notice")
	scene.start_or_resume()
	check(not scene.services.request_test_rewarded_ad(), "No test ad during duel")
	scene.sound.stream_player.stop()
	scene.sound.stream_player.stream = null
	await create_timer(.1).timeout
	scene.queue_free()
	await process_frame
	Engine.unregister_singleton("KiteGoogleServices")
	mock.queue_free()
	await process_frame
	print("%s: %d native-wiring fixture checks (%d failures; not device tests)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
