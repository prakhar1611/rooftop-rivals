extends RefCounted
## Provider contract. Default implementation is deliberately unavailable.
## Never emit verified=true for a timer, close callback, or client assertion.
signal test_reward_result(operation_id: int, earned: bool, message: String)
signal login_finished(operation_id: int, success: bool, account_label: String)
signal reward_finished(operation_id: int, verified: bool, transaction_id: String)

func capabilities() -> Dictionary:
	return {"account": false, "rewarded_ads": false, "label": "Not configured"}

func start_login(operation_id: int) -> void:
	login_finished.emit(operation_id, false, "")

func cancel_login(_operation_id: int) -> void:
	pass

func logout() -> void:
	pass

func show_rewarded(operation_id: int, _placement: String) -> void:
	reward_finished.emit(operation_id, false, "")

func stop_ads() -> void:
	pass

# TEST path never signals a production reward.
func set_test_eligibility(_adult: bool, _outside_battle: bool, _opted_in: bool) -> void:
	pass

func start_test_rewarded(operation_id: int) -> void:
	test_reward_result.emit(operation_id, false, "Test provider unavailable")

func show_privacy_options() -> void:
	pass
