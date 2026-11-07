extends SceneTree
const Battle = preload("res://scripts/battle_model.gd")
var failures := 0
var matches := 0

func play(seed_number: int, level: int, strategy: String):
	var model = Battle.new()
	model.reset(seed_number, level)
	var easing := false
	for tick in range(7201):
		var direction := Vector2.ZERO
		var pulling := true
		var releasing := false
		if strategy == "balanced":
			if model.player_tension > .78:
				easing = true
			if model.player_tension < .43:
				easing = false
			var target := Vector2(5.0 + sin(model.time * 1.6) * 3.0, 20.0)
			var difference := target - Vector2(model.player.x, model.player.y)
			direction = Vector2(difference.x, -difference.y).limit_length(1.0)
			pulling = model.contact and not easing
			releasing = easing
		elif strategy == "release":
			pulling = false
			releasing = true
		model.step(direction, pulling, releasing)
		if model.state == "finished":
			break
	matches += 1
	if model.state != "finished" or model.result_reason.is_empty() or model.time > Battle.ROUND_LIMIT:
		push_error("Unresolved/invalid match seed %d level %d strategy %s" % [seed_number, level, strategy])
		failures += 1
	if not model.player.is_finite() or not model.rival.is_finite() or not is_finite(model.player_health):
		push_error("Non-finite match state")
		failures += 1
	return model

func _initialize() -> void:
	for level in range(3):
		var wins := 0
		for seed_number in [0, 1, 2, 23, 42, 97, 991, -5]:
			var model = play(seed_number, level, "balanced")
			if model.result == "win":
				wins += 1
			if level < 2 and model.result != "win":
				push_error("Balanced strategy should win on Breezy/Rooftop seed %d level %d" % [seed_number, level])
				failures += 1
			var overpull = play(seed_number, level, "overpull")
			if overpull.result != "loss":
				push_error("Sustained over-pull must lose")
				failures += 1
			var release = play(seed_number, level, "release")
			if release.score != 0 or release.combo != 0:
				push_error("Passive release cannot farm score")
				failures += 1
		print("Difficulty %d balanced strategy wins: %d/8" % [level, wins])
	print("%s: %d full seeded matches (%d failures)" % ["PASS" if failures == 0 else "FAIL", matches, failures])
	quit(0 if failures == 0 else 1)
