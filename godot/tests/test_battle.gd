extends SceneTree

const Battle = preload("res://scripts/battle_model.gd")
var checks := 0
var failures := 0

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		push_error("FAIL: " + message)
		failures += 1

func _initialize() -> void:
	var model = Battle.new()
	expect(model.state == "ready", "Ready before play")
	model.reset()
	expect(model.state == "playing" and model.player_health == 100, "Reset starts full-health round")
	var start: Vector3 = model.player
	for i in range(60):
		model.step(Vector2.RIGHT, false, false)
	expect(model.player.x > start.x, "Right input moves kite right")
	var y_before: float = model.player.y
	for i in range(60):
		model.step(Vector2.UP, false, false)
	expect(model.player.y > y_before, "Up input raises kite")
	model.reset()
	for i in range(120):
		model.step(Vector2.ZERO, true, false)
	expect(model.player_tension > .6, "Pull increases tension")
	var tension_before: float = model.player_tension
	for i in range(60):
		model.step(Vector2.ZERO, true, true)
	expect(model.player_tension < tension_before, "Release takes priority over pull")
	model.reset()
	model.player = Vector3(7, 19, -9)
	model.rival = Vector3(-7, 19, -9)
	expect(model.strings_touch(), "Crossed 3D tether segments contact")
	model.rival = Vector3(10, 19, -9)
	model.player = Vector3(-10, 19, -9)
	expect(not model.strings_touch(), "Separated strings do not contact")
	model.reset()
	model.player_tension = 1.0
	model.player = Vector3(-14, 27, -9)
	model.rival = Vector3(14, 10, -9)
	model.step(Vector2.ZERO, true, false)
	expect(model.player_health < 100, "Overtension causes self-damage")
	model.reset()
	for i in range(1200):
		model.step(Vector2(1, -1), false, true)
	expect(model.player.x <= 14 and model.player.y <= 27, "Movement stays within arena")
	# Same seed + tick input produces the same state. No external intelligence.
	var a = Battle.new()
	var b = Battle.new()
	a.reset(42)
	b.reset(42)
	for i in range(600):
		var direction := Vector2(sin(i * .02), cos(i * .03))
		a.step(direction, i % 80 < 50, i % 80 >= 50)
		b.step(direction, i % 80 < 50, i % 80 >= 50)
	expect(a.player == b.player and a.rival == b.rival and a.player_health == b.player_health, "Fixed-step determinism")
	model.reset()
	model.rival_health = .001
	model.player = Vector3(7, 19, -9)
	model.rival = Vector3(-7, 19, -9)
	model.player_tension = .6
	model.step(Vector2.RIGHT, true, false)
	expect(model.state == "finished" and model.result == "win", "Can win by cutting opponent")
	model.reset()
	model.player_health = .001
	model.player_tension = 1.0
	model.step(Vector2.ZERO, true, false)
	expect(model.state == "finished" and model.result == "loss", "Can lose by overtension")
	var final_time: float = model.time
	model.step(Vector2.RIGHT, true, false)
	expect(model.time == final_time, "Finished round stops simulation")
	model.reset()
	expect(model.result == "" and model.player_health == 100 and model.rival_health == 100 and model.time == 0, "Replay resets state")
	model.time = 119.99
	model.player_health = 80
	model.rival_health = 50
	model.step(Vector2.ZERO, false, false)
	expect(model.state == "finished" and model.result == "win", "Timer resolves by remaining string health")
	# Full reset must clear presentation state as well as physical state.
	model.reset(-5, 2)
	expect(model.difficulty == 2 and model.seed_value == -5, "Explicit difficulty and seed")
	expect(model.score == 0 and model.combo == 0 and model.best_combo == 0 and model.events.is_empty() and model.result_reason == "" and model.clash_position == Vector3.ZERO, "Reset clears all match presentation state")
	model.reset()
	expect(model.difficulty == 1, "No-argument reset restores balanced difficulty")
	model.reset(23, 100)
	expect(model.difficulty == 2, "Out-of-range difficulty is clamped")
	model.reset()
	var snapshot: Vector3 = model.player
	model.step(Vector2.RIGHT, true, false, NAN)
	model.step(Vector2.RIGHT, true, false, INF)
	model.step(Vector2.RIGHT, true, false, -1.0)
	expect(model.time == 0.0 and model.player == snapshot, "Invalid time deltas cannot corrupt state")
	model.step(Vector2(NAN, INF), false, false)
	expect(model.player.is_finite() and model.rival.is_finite(), "Invalid steering becomes neutral")
	model.reset()
	model.time = Battle.ROUND_LIMIT - 0.001
	model.player_health = 80.0
	model.rival_health = 79.0
	model.step(Vector2.ZERO, false, false)
	expect(model.result == "draw" and model.result_reason == "time_draw" and model.time == Battle.ROUND_LIMIT, "Close timeout ties and time clamps exactly")
	model.reset()
	model.player = Vector3(7, 19, -9)
	model.rival = Vector3(-7, 19, -9)
	model.player_tension = .6
	model.step(Vector2.ZERO, true, false)
	expect("clash" in model.events and model.combo == 1 and model.score > 0, "Clean crossing emits clash and awards score")
	model.step(Vector2.ZERO, true, false)
	expect(not "clash" in model.events, "Clash event only fires on contact entry")
	model.player_health = 0.0
	model.rival_health = 0.0
	model.step(Vector2.ZERO, false, false)
	expect(model.result == "draw" and model.result_reason == "double_cut" and "round_end" in model.events, "Simultaneous cuts finish once with explicit reason")
	var final_score: int = model.score
	model.finish("win")
	expect(model.result == "draw" and model.score == final_score, "Finish cannot award duplicate bonuses")
	for level in range(3):
		for seed_number in [-5, 0, 23, 97]:
			a.reset(seed_number, level)
			b.reset(seed_number, level)
			for tick in range(1800):
				var input := Vector2(sin(tick * .02), cos(tick * .03))
				a.step(input, tick % 80 < 50, tick % 80 >= 50)
				b.step(input, tick % 80 < 50, tick % 80 >= 50)
				expect(a.events == b.events, "Seeded events are deterministic")
				expect(a.player.is_finite() and a.rival.is_finite() and a.player.x >= -14 and a.player.x <= 14 and a.player.y >= 10 and a.player.y <= 27 and a.player_tension >= .08 and a.player_tension <= 1, "Finite bounded simulation")
			expect(a.player == b.player and a.rival == b.rival and a.score == b.score and a.result == b.result and a.player_health == b.player_health and a.rival_health == b.rival_health, "Difficulty-seeded full state determinism")
	print("%s: %d model checks (%d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
