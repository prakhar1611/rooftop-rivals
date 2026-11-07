extends SceneTree
const Services = preload("res://scripts/services/game_services.gd")
const Bridge = preload("res://scripts/services/native_provider_bridge.gd")

class TestProvider extends "res://scripts/services/service_provider.gd":
	var login_request := -1
	var ad_request := -1
	var stops := 0
	var test_request := -1
	var test_eligibility := []
	func capabilities() -> Dictionary:
		return {"account": true, "rewarded_ads": true, "test_rewarded_ads": true, "label": "UNIT TEST DOUBLE: not real login or ads"}
	func start_login(id: int) -> void:
		login_request = id
	func show_rewarded(id: int, _placement: String) -> void:
		ad_request = id
	func set_test_eligibility(adult: bool, outside_battle: bool, opted_in: bool) -> void:
		test_eligibility = [adult, outside_battle, opted_in]
	func start_test_rewarded(id: int) -> void:
		test_request = id
	func stop_ads() -> void:
		stops += 1

# JNI-style metadata double: most Java names intentionally are NOT GDScript
# methods, so Object.has_method would incorrectly report this contract absent.
class JniMetadataDouble extends RefCounted:
	signal login_result(operation_id: int, authenticated: bool)
	signal reward_result(operation_id: int, transaction_id: String)
	signal test_reward_result(operation_id: int, earned: bool, message: String)
	var methods := ["capabilities", "start_login", "cancel_login", "logout", "show_rewarded", "stop_ads", "is_reward_verified", "start_test_rewarded", "set_test_eligibility", "show_privacy_options"]
	func has_java_method(method: String) -> bool:
		return method in methods
	func capabilities() -> Dictionary:
		return {"account": false, "rewarded_ads": false, "test_rewarded_ads": true, "privacy_options": true}

var failures := 0
var checks := 0
var rewards := 0
var demo_rewards := 0
var notices: Array[String] = []
func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func _initialize() -> void:
	var s = Services.new()
	root.add_child(s)
	s.reward_granted.connect(func(_p): rewards += 1)
	s.demo_reward_earned.connect(func(): demo_rewards += 1)
	s.notice.connect(func(message: String): notices.append(message))
	check(not s.get_status().account_available, "Default login unavailable")
	check(not s.request_rewarded_ad(), "Default ads disabled")
	s.login()
	check(s.get_status().account_status == "Guest", "Unavailable login stays guest")
	var p = TestProvider.new()
	s.configure(p, true, true)
	check(not s.request_rewarded_ad(), "Unknown age and no consent block ads")
	s.set_ad_consent(true)
	check(not s.request_rewarded_ad(), "Unknown age blocks ads with consent")
	s.set_age_eligibility("underage")
	check(not s.request_rewarded_ad(), "Underage blocks ads")
	s.set_age_eligibility("adult")
	s.set_in_battle(true)
	check(not s.request_rewarded_ad(), "Midbattle ads blocked")
	s.set_in_battle(false)
	check(not s.request_rewarded_ad("midbattle"), "Unapproved placement blocked")
	check(s.request_rewarded_ad(), "Eligible postmatch request")
	check(not s.request_rewarded_ad(), "Duplicate request blocked")
	p.reward_finished.emit(p.ad_request, false, "failed")
	check(rewards == 0, "Failure grants nothing")
	s.request_rewarded_ad()
	var old_ad: int = p.ad_request
	s.set_ad_consent(false)
	p.reward_finished.emit(old_ad, true, "withdrawn")
	check(rewards == 0 and p.stops > 0, "Withdrawal stops provider and ignores late callback")
	s.set_ad_consent(true)
	s.request_rewarded_ad()
	p.reward_finished.emit(p.ad_request, true, "verified-1")
	p.reward_finished.emit(p.ad_request, true, "verified-1")
	check(rewards == 1, "Completion grants exactly once")
	s.request_rewarded_ad()
	p.reward_finished.emit(p.ad_request, true, "verified-1")
	check(rewards == 1, "Replayed transaction rejected")
	s.request_rewarded_ad()
	p.reward_finished.emit(p.ad_request, true, "")
	check(rewards == 1, "Missing transaction rejected")
	s.request_rewarded_ad()
	old_ad = p.ad_request
	s.cancel_rewarded_ad()
	p.reward_finished.emit(old_ad, true, "cancelled")
	check(rewards == 1, "Cancelled ad cannot reward")
	s.login()
	var old_login: int = p.login_request
	s.cancel_login()
	p.login_finished.emit(old_login, true, "token must never be displayed")
	check(s.get_status().account_status == "Guest", "Cancelled login ignores completion")
	s.login()
	old_login = p.login_request
	s.logout()
	p.login_finished.emit(old_login, true, "")
	check(s.get_status().account_status == "Guest", "Logout ignores in-flight login")
	s.login()
	p.login_finished.emit(p.login_request, true, "private info")
	check(s.get_status().account_status == "Signed in", "Verified provider login supported without displaying PII")
	s.clear_local_account()
	check(s.get_status().account_status == "Guest", "Local clear restores guest")
	s.login()
	s._login_deadline = 0
	s._process(0)
	p.login_finished.emit(p.login_request, true, "")
	check(s.get_status().account_status == "Guest", "Timeout rejects late login")
	s.request_rewarded_ad()
	s._ad_deadline = 0
	s._process(0)
	p.reward_finished.emit(p.ad_request, true, "late")
	check(rewards == 1, "Timeout rejects late ad")
	check(not s.request_test_rewarded_ad(), "Test needs separate opt-in despite production consent")
	s.set_test_ad_opt_in(true)
	s.set_age_eligibility("unknown")
	check(not s.request_test_rewarded_ad(), "Unknown age blocks tests")
	s.set_age_eligibility("underage")
	check(not s.request_test_rewarded_ad(), "Underage blocks tests")
	s.set_age_eligibility("adult")
	s.set_in_battle(true)
	check(not s.request_test_rewarded_ad(), "Battle blocks tests")
	s.set_in_battle(false)
	check(s.request_test_rewarded_ad(), "Explicit eligible test starts")
	check(p.test_eligibility == [true, true, true], "Native receives eligibility")
	check(s.get_status().test_busy, "Test busy exposed")
	check(not s.request_test_rewarded_ad() and not s.request_rewarded_ad(), "No overlapping test or production requests")
	var notice_count := notices.size()
	p.test_reward_result.emit(p.test_request, true, "test earned")
	p.test_reward_result.emit(p.test_request, true, "duplicate")
	check(demo_rewards == 1 and rewards == 1, "Test earns demo once, never production reward")
	check(notices.size() == notice_count, "Earned test emits demo only, not provider notice")
	s.request_test_rewarded_ad()
	p.test_reward_result.emit(p.test_request, false, "No fill")
	check(demo_rewards == 1, "Test failure grants nothing")
	check(notices.back() == "No fill No saved rewards were changed.", "Fixed provider failure reaches notice with no-saved-reward wording")
	s.request_test_rewarded_ad()
	p.test_reward_result.emit(p.test_request, false, "   ")
	check(notices.back() == "Test ad did not earn a demo reward. No saved rewards were changed.", "Empty provider failure uses safe fallback")
	s.request_test_rewarded_ad()
	p.test_reward_result.emit(p.test_request, false, "Error\n" + "x".repeat(400))
	check(notices.back().length() <= 231 and not notices.back().contains("\n"), "Provider diagnostic is bounded and single line")
	s.request_test_rewarded_ad()
	var old_test: int = p.test_request
	s.set_test_ad_opt_in(false)
	p.test_reward_result.emit(old_test, true, "late")
	check(demo_rewards == 1 and p.test_eligibility[2] == false, "Revocation cancels test and native eligibility")
	s.set_test_ad_opt_in(true)
	s.request_test_rewarded_ad()
	old_test = p.test_request
	s.set_in_battle(true)
	p.test_reward_result.emit(old_test, true, "late battle")
	check(demo_rewards == 1, "Entering battle invalidates test")
	s.set_in_battle(false)
	s.request_test_rewarded_ad()
	old_test = p.test_request
	s.logout()
	p.test_reward_result.emit(old_test, true, "late logout")
	check(demo_rewards == 1 and not s.get_status().test_ad_opt_in, "Logout invalidates test and revokes opt-in")
	s.set_test_ad_opt_in(true)
	s.request_test_rewarded_ad()
	s._test_deadline = 0
	p.test_reward_result.emit(p.test_request, true, "late before process")
	check(demo_rewards == 1 and not s.get_status().test_busy, "Deadline blocks test before next process tick")
	s.request_test_rewarded_ad()
	s._test_deadline = 0
	s._process(0)
	check(not s.get_status().test_busy, "Test timeout clears busy")
	s.request_test_rewarded_ad()
	old_test = p.test_request
	s.cancel_test_rewarded_ad()
	p.test_reward_result.emit(old_test, true, "cancelled")
	check(demo_rewards == 1, "Explicit test cancellation blocks late completion")
	var bridge = Bridge.new()
	check(not bridge.capabilities().account, "Missing native plugin fails closed")
	check(not bridge.capabilities().get("test_rewarded_ads", false), "Missing native plugin tests fail closed")
	var jni = JniMetadataDouble.new()
	var jni_bridge = Bridge.new(jni)
	check(not jni.has_method("start_login") and jni_bridge._valid(), "JNI method map supports absent Object methods")
	check(jni_bridge.capabilities().test_rewarded_ads, "JNI test methods discovered")
	check(jni_bridge.capabilities().privacy_options, "JNI privacy method discovered")
	jni.methods.erase("show_privacy_options")
	check(not jni_bridge.capabilities().privacy_options, "JNI missing privacy method fails closed")
	jni.methods.erase("start_test_rewarded")
	check(not jni_bridge.capabilities().test_rewarded_ads, "JNI missing test method fails closed")
	jni.methods.erase("logout")
	check(not jni_bridge._valid(), "JNI missing required method fails closed")
	var ordinary_bridge = Bridge.new(p)
	check(ordinary_bridge._has_bridge_method("start_login"), "Ordinary Object method fallback preserved")
	s.configure(null)
	p.login_finished.emit(p.login_request, true, "")
	check(s.get_status().account_status == "Guest", "Provider replacement disconnects old callbacks")
	s.free()
	print("Service tests: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
