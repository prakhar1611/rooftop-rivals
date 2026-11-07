extends "res://scripts/services/service_provider.gd"
## Optional adapter for explicitly supplied Android plugin; no auto-discovery/init.
## Supply the bridge explicitly after deployment configuration and legal review.
## Bridge must hold credentials in Android Keystore and verify rewards server-side.
var _bridge: Object

func _init(bridge: Object = null) -> void:
	_bridge = bridge
	if _valid():
		_bridge.login_result.connect(_login_result)
		_bridge.reward_result.connect(_reward_result)
		if _valid_test():
			_bridge.test_reward_result.connect(_test_reward_result)

func _has_bridge_method(method: String) -> bool:
	if not is_instance_valid(_bridge):
		return false
	# Godot 4.6 JNISingleton keeps Java methods in a separate method map.
	# Ordinary Objects/test doubles continue using Object.has_method.
	if _bridge.has_method("has_java_method"):
		return bool(_bridge.has_java_method(method))
	return _bridge.has_method(method)

func _valid() -> bool:
	if not is_instance_valid(_bridge):
		return false
	for method in ["capabilities", "start_login", "cancel_login", "logout", "show_rewarded", "stop_ads", "is_reward_verified"]:
		if not _has_bridge_method(method):
			return false
	return _bridge.has_signal("login_result") and _bridge.has_signal("reward_result")

func capabilities() -> Dictionary:
	if not _valid():
		return super.capabilities()
	var caps: Dictionary = _bridge.capabilities().duplicate()
	caps["test_rewarded_ads"] = _valid_test() and bool(caps.get("test_rewarded_ads", false))
	caps["privacy_options"] = _has_bridge_method("show_privacy_options") and bool(caps.get("privacy_options", false))
	return caps

func start_login(operation_id: int) -> void:
	if _valid():
		_bridge.start_login(operation_id)
	else:
		login_finished.emit(operation_id, false, "")

func cancel_login(operation_id: int) -> void:
	if _valid():
		_bridge.cancel_login(operation_id)

func logout() -> void:
	if _valid():
		_bridge.logout()

func show_rewarded(operation_id: int, placement: String) -> void:
	if _valid():
		_bridge.show_rewarded(operation_id, placement)
	else:
		reward_finished.emit(operation_id, false, "")

func stop_ads() -> void:
	if _valid():
		_bridge.stop_ads()

func _login_result(operation_id: int, authenticated: bool) -> void:
	login_finished.emit(operation_id, authenticated, "")

func _reward_result(operation_id: int, transaction_id: String) -> void:
	var verified: bool = _valid() and _bridge.is_reward_verified(operation_id, transaction_id)
	reward_finished.emit(operation_id, verified, transaction_id)

func _valid_test() -> bool:
	return _valid() and _has_bridge_method("start_test_rewarded") and _has_bridge_method("set_test_eligibility") and _bridge.has_signal("test_reward_result")

func set_test_eligibility(adult: bool, outside_battle: bool, opted_in: bool) -> void:
	if _valid_test():
		_bridge.set_test_eligibility(adult, outside_battle, opted_in)

func start_test_rewarded(operation_id: int) -> void:
	if _valid_test():
		_bridge.start_test_rewarded(operation_id)
	else:
		test_reward_result.emit(operation_id, false, "Native test provider unavailable")

func _test_reward_result(operation_id: int, earned: bool, message: String) -> void:
	test_reward_result.emit(operation_id, earned, message)

func show_privacy_options() -> void:
	if _valid() and _has_bridge_method("show_privacy_options"):
		_bridge.show_privacy_options()
