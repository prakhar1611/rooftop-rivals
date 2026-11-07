extends SceneTree
## Real simulation feasibility, not synthetic completion: no health/stat edits.
## These bots establish a deterministic floor, not a substitute for human playtesting.
const Battle = preload("res://scripts/battle_model.gd")
const Campaign = preload("res://scripts/campaign.gd")
var failures := 0
var checks := 0
var matches := 0

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		push_error("FAIL: " + message)
		failures += 1

func play(encounter: Dictionary, strategy: String):
	var model = Battle.new()
	model.reset(int(encounter.get("seed", 23)), int(encounter.get("difficulty", 1)))
	model.configure_encounter(encounter)
	var easing := false
	for tick in range(7201):
		var direction := Vector2.ZERO
		var pulling := false
		var releasing := false
		if strategy in ["balanced", "adaptive", "climbing"]:
			if model.player_tension > 0.76:
				easing = true
			if model.player_tension < 0.43:
				easing = false
			var target := Vector2(5.0 + sin(model.time * 1.6) * 3.0, 20.0)
			if strategy != "balanced":
				target = Vector2(clampf(model.rival.x + 6.5 + sin(model.time * 1.8) * 3.0, -7.0, 12.0), clampf(model.rival.y + 1.1, 14.0, 27.0))
				if model.wind_warning and model.player_tension > 0.6:
					easing = true
				if strategy == "climbing":
					target.x = 5.0 + sin(model.time * 1.6) * 3.0
			var difference := target - Vector2(model.player.x, model.player.y)
			direction = Vector2(difference.x, -difference.y).limit_length(1.0)
			pulling = model.contact and not easing
			releasing = easing
		elif strategy == "release":
			releasing = true
		elif strategy == "overpull":
			pulling = true
		model.step(direction, pulling, releasing)
		if model.state == "finished":
			break
	matches += 1
	expect(model.state == "finished" and not model.result_reason.is_empty() and model.time <= Battle.ROUND_LIMIT, "Every simulated encounter resolves within the round limit")
	expect(model.encounter_id == str(encounter.get("id", "free_duel")), "Battle retains the encounter identity for progression")
	return model

func _initialize() -> void:
	var basic_wins := 0
	var adaptive_wins := 0
	for stage in Campaign.STAGES:
		var basic = play(stage, "balanced")
		var adaptive = play(stage, "adaptive")
		var climbing = play(stage, "climbing")
		basic_wins += 1 if basic.result == "win" else 0
		adaptive_wins += 1 if adaptive.result == "win" else 0
		if int(stage.index) < 3:
			expect(basic.result == "win" and basic.player_health > 50.0, "Starter chapter rewards a simple controlled pull/ease rhythm")
		expect(adaptive.result == "win", "Every campaign rival is beatable using visible position, tension and wind cues")
		var earns_all: bool = (adaptive.result == "win" and adaptive.player_health >= float(stage.medal_health) and adaptive.clean_cut_time >= float(stage.medal_clean_time)) or (climbing.result == "win" and climbing.player_health >= float(stage.medal_health) and climbing.clean_cut_time >= float(stage.medal_clean_time))
		expect(earns_all, "Every campaign medal target is attainable without stat upgrades")
		if stage.style == "champion":
			expect(basic.result != "win", "Final champions punish the repeated fixed-height pattern")
		print("%s: simple %s (%.0f%%), tactical %s (%.0f%%, %.1fs clean)" % [stage.id, basic.result, basic.player_health, adaptive.result, adaptive.player_health, adaptive.clean_cut_time])
	expect(basic_wins >= 3 and basic_wins < Campaign.STAGES.size(), "Basic strategy succeeds early but does not solve the campaign")
	expect(adaptive_wins == Campaign.STAGES.size(), "All campaign stages remain tactically winnable")

	# Passive and brute-force actions must never become a progression strategy.
	for level in range(3):
		for style in Battle.STYLES:
			for seed_number in [-5, 0, 23, 97]:
				var encounter := {"id": "exploit_check", "seed": seed_number, "difficulty": level, "style": style, "wind_strength": 1.5, "gust_strength": 1.5}
				for strategy in ["idle", "release", "overpull"]:
					var model = play(encounter, strategy)
					expect(model.result != "win", "Idle, release-only and endless pull cannot farm wins")
					if strategy != "overpull":
						expect(model.score == 0 and model.combo == 0 and model.damage_dealt == 0.0, "Passive strategies cannot damage strings or farm points")
					else:
						expect(model.result == "loss", "Endless pull always loses to strain or a cut")
	print("PASS balance summary: simple %d/12, tactical %d/12 campaign wins" % [basic_wins, adaptive_wins])
	print("%s: %d campaign/exploit matches, %d checks (%d failures)" % ["PASS" if failures == 0 else "FAIL", matches, checks, failures])
	quit(0 if failures == 0 else 1)
