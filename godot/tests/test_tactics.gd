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
	model.reset(23, 0)
	model.configure_encounter({"id": "harbour_final", "style": "CHAMPION", "wind_strength": 2.0, "gust_strength": 1.8, "gust_interval": 8.0, "gust_duration": 2.4, "gust_warning": 2.0})
	expect(model.encounter_id == "harbour_final" and model.opponent_style == "CHAMPION", "Encounter metadata selects named rival")
	expect(model.player_health == 100.0 and model.rival_health == 100.0 and model.difficulty == 0, "Encounter never grants power or changes selected difficulty")
	expect(model.wind_strength == 2.0 and model.gust_strength == 1.8 and model.gust_interval == 8.0 and model.gust_duration == 2.4 and model.gust_warning == 2.0, "Encounter weather parameters applied")
	model.configure_encounter({"style": "unknown", "wind_strength": NAN, "gust_strength": INF, "gust_interval": "invalid"})
	expect(model.opponent_style == "CHAMPION" and model.wind_strength == 2.0 and model.gust_strength == 1.8 and model.gust_interval == 8.0, "Malformed configuration preserves finite valid settings")
	model.configure_encounter({"wind_strength": -9, "gust_strength": 500, "gust_interval": 1, "gust_duration": 500, "gust_warning": 500})
	expect(model.wind_strength == 0.0 and model.gust_strength == 2.5 and model.gust_duration == 3.0 and model.gust_warning == 2.5, "Extreme weather values clamp")
	expect(model.gust_interval >= model.gust_duration + model.gust_warning + 0.75, "Extreme weather retains a calm gap")
	model.step(Vector2.ZERO, false, false)
	model.configure_encounter({"id": "exploit", "style": "sweeper", "gust_strength": 0.0})
	expect(model.encounter_id == "harbour_final" and model.opponent_style == "CHAMPION" and model.gust_strength == 2.5, "Started encounter cannot be reconfigured")
	model.reset(23, 0)
	expect(model.encounter_id == "free_duel" and model.opponent_style == "PRESSURER" and model.wind_strength == 1.0 and model.gust_strength == 0.7, "Reset clears encounter and restores legacy personality")
	expect(not model.wind_warning and not model.gust_active and model.advantage == 0.0 and model.crossing_angle == 0.0 and not model.feedback.is_empty() and not model.rival_intent.is_empty(), "Reset clears tactical presentation")

	for configuration in [{}, {"gust_strength": 2.5, "gust_interval": 5.0, "gust_duration": 3.0, "gust_warning": 2.5}]:
		model.reset(11, 0)
		model.configure_encounter(configuration)
		var warning_seen := false
		var warned_at := 0.0
		var warnings := 0
		var gusts := 0
		for tick in range(1800):
			model.step(Vector2.ZERO, false, true)
			if "gust_warning" in model.events:
				warning_seen = true
				warned_at = model.time
				warnings += 1
			if "gust" in model.events:
				expect(warning_seen, "Every gust has its own preceding warning")
				expect(model.time - warned_at >= model.gust_warning - Battle.STEP * 2.0, "Gust warning lasts the configured readable duration")
				warning_seen = false
				gusts += 1
			expect(not (model.wind_warning and model.gust_active), "Warning and active gust phases stay distinct")
			expect(model.wind.is_finite() and model.wind.length() < 10.0, "Wind remains finite and bounded")
		expect(gusts >= 2 and warnings >= gusts, "Repeated scheduled gusts occur")
	model.reset(11)
	model.configure_encounter({"gust_strength": 0.0, "wind_strength": 0.0})
	for tick in range(1500):
		model.step(Vector2.ZERO, false, true)
		expect(model.wind == Vector2.ZERO and not model.wind_warning and not model.gust_active, "Calm encounter disables gusts and ambient wind")

	# Matched crossings differ only in height, with identical player input/tension.
	var high = Battle.new()
	var low = Battle.new()
	for m in [high, low]:
		m.reset(3)
		m.configure_encounter({"wind_strength": 0.0, "gust_strength": 0.0})
		m.player = Vector3(7.0, 19.0, -9.0)
		m.rival = Vector3(-7.0, 19.0, -9.0)
		m.player_tension = 0.6
	high.player.y += 0.8
	low.player.y -= 0.8
	high.step(Vector2.ZERO, true, false)
	low.step(Vector2.ZERO, true, false)
	expect(high.contact and low.contact, "Both comparison crossings physically touch")
	expect(high.advantage > 0.25 and low.advantage < -0.25, "Height produces signed tactical leverage")
	expect(high.last_rival_damage > low.last_rival_damage * 1.30, "Favorable position meaningfully improves a clean cut")
	expect(model.cut_force(0.6, false, 7.0) == 0.0, "No passive cutting damage")
	expect(model._stroke_bite(4.0) < model._stroke_bite(0.5) * 0.5, "Indefinite held pull loses cutting bite")
	model.reset()
	model.configure_encounter({"wind_strength": 0.0, "gust_strength": 0.0})
	model.player = Vector3(14.0, 27.0, -9.0)
	model.step(Vector2(1.0, -1.0), true, false)
	expect(model.player_velocity == Vector2.ZERO, "Arena edge cannot create fake sawing speed")
	model._gust_load = 0.15
	var loaded: float = model.update_tension(0.6, true, false, 1.0, 0.05)
	model._gust_load = 0.0
	var calm: float = model.update_tension(0.6, true, false, 1.0, 0.05)
	expect(loaded > calm, "Gust adds real line strain while pulling")

	var signatures: Array[Vector3] = []
	for style in Battle.STYLES:
		var a = Battle.new()
		var b = Battle.new()
		a.reset(-5, 2)
		b.reset(-5, 2)
		var encounter := {"id": style + "_test", "style": style, "wind_strength": 1.3, "gust_strength": 1.8, "gust_interval": 7.0}
		a.configure_encounter(encounter)
		b.configure_encounter(encounter)
		var saw_windup := false
		var attack_started := false
		var was_pulling := false
		for tick in range(900):
			var direction := Vector2(sin(tick * 0.013), -cos(tick * 0.017))
			a.step(direction, tick % 120 < 70, tick % 120 >= 70)
			b.step(direction, tick % 120 < 70, tick % 120 >= 70)
			if a.opponent_state == "WIND UP":
				saw_windup = true
			if a._ai_pull and not was_pulling:
				expect(saw_windup, "Rival attack has a visible wind-up")
				attack_started = true
				saw_windup = false
			was_pulling = a._ai_pull
			expect(a.player == b.player and a.rival == b.rival and a.player_health == b.player_health and a.rival_health == b.rival_health and a.events == b.events and a.rival_intent == b.rival_intent, "Configured encounter remains fully deterministic")
			expect(is_finite(a.advantage) and absf(a.advantage) <= 1.0 and a.crossing_angle >= 0.0 and a.crossing_angle <= 180.0 and not a.feedback.is_empty() and not a.rival_intent.is_empty(), "Readable tactical data is bounded and populated")
			expect(a.player.is_finite() and a.rival.is_finite() and a.player_health >= 0.0 and a.player_health <= 100.0 and a.rival_health >= 0.0 and a.rival_health <= 100.0, "Every archetype stays finite and health-bounded")
		expect(attack_started, "Every archetype engages instead of waiting forever")
		expect(a.rival not in signatures, "Archetypes produce distinct flight patterns")
		signatures.append(a.rival)
	print("%s: %d tactical checks (%d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
