extends Node
## Offline-first coordinator; settings and credentials are NOT persisted here.
## Inject an audited provider explicitly; the default never starts a network SDK.
signal status_changed()
signal reward_granted(placement: String)
signal demo_reward_earned()
signal notice(message: String)

const Provider = preload("res://scripts/services/service_provider.gd")
const TIMEOUT_SECONDS := 120.0
var _provider: RefCounted = Provider.new()
var _accounts_enabled := false
var _ads_enabled := false
var _consent := false
var _age := "unknown"
var _in_battle := false
var _account_status := "Guest"
var _serial := 0
var _login_id := -1
var _ad_id := -1
var _test_id := -1
var _test_opt_in := false
var _test_deadline := 0.0
var _placement := ""
var _login_deadline := 0.0
var _ad_deadline := 0.0
var _seen_transactions: Dictionary = {}

func _init() -> void:
	_connect_provider()

func _connect_provider() -> void:
	_provider.login_finished.connect(_on_login_finished)
	_provider.reward_finished.connect(_on_reward_finished)
	_provider.test_reward_result.connect(_on_test_reward_result)

func configure(provider: RefCounted, enable_accounts := false, enable_ads := false) -> void:
	# Clear old state before cancel calls, which can synchronously callback.
	logout()
	_stop_ad()
	_provider.login_finished.disconnect(_on_login_finished)
	_provider.reward_finished.disconnect(_on_reward_finished)
	_provider.test_reward_result.disconnect(_on_test_reward_result)
	_provider = provider if provider != null else Provider.new()
	_accounts_enabled = enable_accounts
	_ads_enabled = enable_ads
	_consent = false
	_test_opt_in = false
	_age = "unknown"
	_connect_provider()
	status_changed.emit()

func get_status() -> Dictionary:
	var caps: Dictionary = _provider.capabilities()
	return {
		"account_status": _account_status,
		"account_available": _accounts_enabled and bool(caps.get("account", false)),
		"ads_available": _ads_enabled and bool(caps.get("rewarded_ads", false)),
		"provider_label": str(caps.get("label", "Not configured")),
		"ad_consent": _consent, "age_eligibility": _age,
		"reward_available": _can_show_ad(),
		"busy": _login_id >= 0 or _ad_id >= 0 or _test_id >= 0,
		"test_ads_available": bool(caps.get("test_rewarded_ads", false)),
		"test_busy": _test_id >= 0, "test_ad_opt_in": _test_opt_in,
		"test_reward_available": _can_show_test_ad(),
		"privacy_options_available": bool(caps.get("privacy_options", false)),
		"login_pending": _login_id >= 0, "ad_pending": _ad_id >= 0,
		"telemetry_enabled": false,
	}

func login() -> void:
	if _login_id >= 0 or _ad_id >= 0 or _test_id >= 0:
		return
	if not get_status()["account_available"]:
		notice.emit("Login is not configured. You can keep playing as a guest.")
		return
	_serial += 1
	_login_id = _serial
	_login_deadline = _now() + TIMEOUT_SECONDS
	status_changed.emit()
	_provider.start_login(_login_id)

func cancel_login() -> void:
	var old := _login_id
	_login_id = -1
	if old >= 0:
		_provider.cancel_login(old)
	status_changed.emit()

func logout() -> void:
	cancel_login()
	_account_status = "Guest"
	_test_opt_in = false
	_stop_ad()
	_provider.logout()
	status_changed.emit()

func clear_local_account() -> void:
	logout()
	notice.emit("Local account session cleared. This does not delete a provider account or cloud data.")

func set_ad_consent(allowed: bool) -> void:
	_consent = allowed
	if not allowed:
		_stop_ad()
	status_changed.emit()

func set_age_eligibility(eligibility: String) -> void:
	_age = eligibility if eligibility in ["adult", "underage"] else "unknown"
	if _age != "adult":
		_stop_ad()
	status_changed.emit()

func set_in_battle(active: bool) -> void:
	_in_battle = active
	if active:
		_stop_ad()
	status_changed.emit()

func _can_show_ad() -> bool:
	return _ads_enabled and bool(_provider.capabilities().get("rewarded_ads", false)) and _consent and _age == "adult" and not _in_battle and _ad_id < 0 and _login_id < 0 and _test_id < 0

func request_rewarded_ad(placement := "post_match") -> bool:
	if not _can_show_ad() or placement != "post_match":
		notice.emit("Optional rewards are unavailable. Guest play is unaffected.")
		return false
	_serial += 1
	_ad_id = _serial
	_placement = placement
	_ad_deadline = _now() + TIMEOUT_SECONDS
	status_changed.emit()
	_provider.show_rewarded(_ad_id, placement)
	return true

func cancel_rewarded_ad() -> void:
	_stop_ad()
	status_changed.emit()

func _stop_ad() -> void:
	_test_id = -1
	_ad_id = -1
	_placement = ""
	_sync_test_eligibility()
	_provider.stop_ads()

func _on_login_finished(operation_id: int, success: bool, _account_label: String) -> void:
	if operation_id != _login_id or _login_id < 0:
		return
	if _now() >= _login_deadline:
		cancel_login()
		return
	_login_id = -1
	# Display no provider-supplied personal information or tokens.
	_account_status = "Signed in" if success else "Guest"
	if not success:
		notice.emit("Sign-in was cancelled or failed. Guest play is available.")
	status_changed.emit()

func _on_reward_finished(operation_id: int, verified: bool, transaction_id: String) -> void:
	if operation_id != _ad_id or _ad_id < 0:
		return
	if _now() >= _ad_deadline:
		cancel_rewarded_ad()
		return
	var placement := _placement
	_ad_id = -1
	_placement = ""
	var eligible := _ads_enabled and _consent and _age == "adult" and not _in_battle
	if verified and eligible and not transaction_id.is_empty() and not _seen_transactions.has(transaction_id):
		_seen_transactions[transaction_id] = true
		reward_granted.emit(placement)
	else:
		notice.emit("No reward was granted. The ad was unavailable, cancelled, or unverified.")
	status_changed.emit()

func set_test_ad_opt_in(allowed: bool) -> void:
	_test_opt_in = allowed
	if not allowed:
		cancel_test_rewarded_ad()
	_sync_test_eligibility()
	status_changed.emit()

func _sync_test_eligibility() -> void:
	_provider.set_test_eligibility(_age == "adult", not _in_battle, _test_opt_in)

func _can_show_test_ad() -> bool:
	return bool(_provider.capabilities().get("test_rewarded_ads", false)) and _test_opt_in and _age == "adult" and not _in_battle and _test_id < 0 and _ad_id < 0 and _login_id < 0

func request_test_rewarded_ad() -> bool:
	if not _can_show_test_ad():
		notice.emit("Google test ads are unavailable or eligibility and opt-in are incomplete.")
		return false
	_serial += 1
	_test_id = _serial
	_test_deadline = _now() + TIMEOUT_SECONDS
	_sync_test_eligibility()
	status_changed.emit()
	_provider.start_test_rewarded(_test_id)
	return true

func cancel_test_rewarded_ad() -> void:
	# stop_ads cancels both paths; invalidate both before synchronous callbacks.
	_stop_ad()
	status_changed.emit()

func show_privacy_options() -> void:
	if not bool(_provider.capabilities().get("privacy_options", false)):
		notice.emit("Provider privacy options are unavailable.")
		return
	# Revokes local eligibility immediately; consent UI cannot grant a reward.
	set_test_ad_opt_in(false)
	set_ad_consent(false)
	_provider.show_privacy_options()

func _on_test_reward_result(operation_id: int, earned: bool, message: String) -> void:
	if operation_id != _test_id or _test_id < 0:
		return
	if _now() >= _test_deadline:
		cancel_test_rewarded_ad()
		return
	_test_id = -1
	if earned and _test_opt_in and _age == "adult" and not _in_battle:
		# Demo notification only. Never connect to currency, score or persistence.
		demo_reward_earned.emit()
	else:
		var detail := message.strip_edges().replace("\n", " ").replace("\r", " ").replace("\t", " ").left(200)
		if detail.is_empty():
			detail = "Test ad did not earn a demo reward."
		notice.emit(detail + " No saved rewards were changed.")
	status_changed.emit()

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _process(_delta: float) -> void:
	if _login_id >= 0 and _now() >= _login_deadline:
		cancel_login()
		notice.emit("Sign-in timed out. Please try again or continue as a guest.")
	if _ad_id >= 0 and _now() >= _ad_deadline:
		cancel_rewarded_ad()
		notice.emit("Ad request timed out. No reward was granted.")

	if _test_id >= 0 and _now() >= _test_deadline:
		cancel_test_rewarded_ad()
		notice.emit("Test ad timed out. No game rewards were changed.")

func _exit_tree() -> void:
	logout()
