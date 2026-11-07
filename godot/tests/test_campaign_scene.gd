extends SceneTree
## Headless integration and font-metric review, not a device/screenshot test.

const Profile = preload("res://scripts/player_profile.gd")
const Campaign = preload("res://scripts/campaign.gd")
const Battle = preload("res://scripts/battle_model.gd")
const TEST_SAVE := "user://campaign_scene_test.json"

class MeasuringHud:
	extends "res://scripts/hud.gd"
	var text_items: Array = []
	var button_items: Array = []
	func card(_rect: Rect2, _color: Color, _radius: int = 18) -> void:
		pass
	func label_at(value: String, at: Vector2, font_size: int, _color: Color = Color.WHITE) -> void:
		text_items.append({"text": value, "rect": Rect2(at - Vector2(0, font_size), font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)), "size": font_size})
	func button(rect: Rect2, value: String, selected: bool = false) -> void:
		super.button(rect, value, selected)
		button_items.append({"text": value, "rect": rect, "width": text_items[-1].rect.size.x})
	func _draw() -> void:
		pass

var checks := 0
var failures := 0
var scene: Node
var hud: Control

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func finish_round(outcome: String) -> void:
	scene.hud.clear_input()
	scene.model.time = Battle.ROUND_LIMIT - .001
	scene.model.player_health = 80.0 if outcome == "win" else (20.0 if outcome == "loss" else 50.0)
	scene.model.rival_health = 20.0 if outcome == "win" else (80.0 if outcome == "loss" else 50.0)
	scene.model.clean_cut_time = 6.0
	scene.input_armed = true
	scene._physics_process(Battle.STEP)
	expect(scene.model.state == "finished" and scene.model.result == outcome, "Finish fixture reaches " + outcome)

func hit(rect: Rect2, role: String, message: String) -> void:
	expect(hud.pick_role(rect.get_center()) == role, message)

func run() -> void:
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.set_physics_process(false)
	scene.set_process(false)
	hud = scene.hud
	scene.profile.data = Profile.DEFAULTS.duplicate(true)
	scene.profile.save_path = TEST_SAVE
	scene.profile.save_allowed = true
	scene.profile.data.sound = false
	scene.apply_settings(false)
	expect(scene.model.state == "ready", "Launch waits at offline home")
	expect(scene.services.get_status().account_status == "Guest", "Guest services preserved")

	for i in range(3):
		hit(Rect2(hud.ui_size.x / 2 - 300 + i * 205, hud.ui_size.y / 2 - 64, 190, 85), ["campaign", "tournament", "quick"][i], "Home mode hit region " + str(i))
	hud.handle_menu_role("campaign")
	for chapter in range(4):
		hit(hud.chapter_rect(chapter), "chapter_" + str(chapter), "Chapter tab hit region " + str(chapter))
	for i in range(3):
		hit(hud.stage_rect(i), "stage_" + str(i), "Stage hit region " + str(i))
	hud.handle_menu_role("stage_1")
	expect(hud.panel == "campaign" and hud.toast.contains("previous"), "Locked stage cannot open briefing")
	hud.handle_menu_role("stage_0")
	expect(hud.panel == "briefing", "Unlocked stage opens briefing")
	hit(hud.start_rect(), "fly_stage", "Briefing challenge hit region")
	hud.back()
	expect(hud.panel == "campaign", "Briefing Back returns to chapter list")
	hud.back()
	expect(hud.panel == "", "Campaign Back returns home")
	hud.activate_primary()
	expect(hud.panel == "briefing" and hud.selected_stage == 0, "Continue campaign selects first incomplete rooftop")
	hud.handle_menu_role("fly_stage")
	expect(scene.play_mode == "campaign" and scene.model.encounter_id == Campaign.STAGES[0].id, "Challenge connects campaign to model")
	expect(scene.model.state == "playing" and hud.panel == "" and scene.services._in_battle, "Campaign begins with services battle guard")
	hud.pull_held = true
	scene.toggle_pause()
	var saved_time: float = scene.model.time
	scene._physics_process(.05)
	expect(scene.paused and scene.model.time == saved_time and not hud.pull_held, "Pause stops time and clears controls")
	hud.handle_menu_role("settings")
	hud.back()
	expect(scene.paused and hud.panel == "", "Settings Back preserves pause")
	hud.activate_primary()
	expect(not scene.paused and scene.play_mode == "campaign" and scene.model.time == saved_time, "Resume preserves campaign encounter")
	finish_round("loss")
	expect(scene.profile.data.matches == 1 and scene.profile.data.stage_medals[0] == 0, "Loss records once and does not unlock")
	hud.activate_primary()
	expect(scene.model.state == "playing" and scene.active_encounter.index == 0, "Loss retry repeats same rooftop")
	finish_round("win")
	expect(scene.profile.data.matches == 2 and scene.profile.data.stage_medals[0] == 3, "Win records aggregate and three medals")
	for _i in range(5):
		scene._physics_process(Battle.STEP)
	expect(scene.profile.data.matches == 2 and scene.profile.data.wins == 1, "Repeated finish ticks do not award again")
	expect(not scene.campaign.record_result(scene.model).accepted, "Repeated result rejected by progression")
	hud.activate_primary()
	expect(scene.active_encounter.index == 1 and scene.model.state == "playing", "Win Next opens following rooftop")
	scene._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	expect(scene.paused and hud.joystick == Vector2.ZERO, "Focus interruption pauses campaign")
	hud.handle_menu_role("home")
	expect(scene.model.state == "ready" and not scene.paused and not scene.services._in_battle, "Leave campaign returns safe home")

	hud.handle_menu_role("tournament")
	hit(hud.start_rect(), "fly_tournament", "Cup entry hit region")
	hud.handle_menu_role("fly_tournament")
	var run_id: int = scene.profile.data.tournament.run_id
	expect(scene.play_mode == "tournament" and scene.active_encounter.index == 0, "Cup starts quarterfinal")
	finish_round("win")
	expect(scene.profile.data.tournament.round == 1 and scene.match_summary.tournament_advanced, "Cup win advances saved round")
	hud.back()
	expect(scene.model.state == "ready" and scene.campaign.has_active_tournament(), "Result Back preserves saved cup")
	scene.start_tournament()
	expect(scene.active_encounter.index == 1 and scene.profile.data.tournament.run_id == run_id, "Cup resume keeps run and round")
	finish_round("win")
	hud.activate_primary()
	expect(scene.active_encounter.index == 2 and scene.model.player_health == 100, "Next cup final resets string")
	finish_round("win")
	expect(scene.profile.data.tournament_titles == 1 and scene.profile.skin_unlocked(5), "Champion awarded one title and cosmetic")
	for _i in range(4):
		scene._physics_process(Battle.STEP)
	expect(scene.profile.data.tournament_titles == 1, "Repeated championship result cannot duplicate title")
	hud.activate_primary()
	expect(scene.model.state == "ready", "Champion Continue returns home")
	scene.start_tournament()
	expect(scene.profile.data.tournament.run_id == run_id + 1, "New cup uses new run")
	finish_round("draw")
	expect(not scene.campaign.has_active_tournament(), "Cup draw eliminates")
	hud.activate_primary()
	expect(scene.model.state == "ready", "Elimination Continue returns home")

	hud.handle_menu_role("quick")
	hud.handle_menu_role("difficulty_2")
	hud.handle_menu_role("fly_quick")
	expect(scene.model.difficulty == 2 and scene.play_mode == "quick", "Quick duel keeps chosen difficulty")
	var medals_before: Array = scene.profile.data.stage_medals.duplicate()
	finish_round("win")
	expect(scene.profile.data.stage_medals == medals_before, "Quick duel cannot unlock campaign stages")
	hud.activate_primary()
	expect(scene.play_mode == "quick" and scene.model.state == "playing", "Quick rematch stays quick")
	scene.return_home()
	hud.handle_menu_role("account")
	hud.handle_menu_role("account_login")
	expect(scene.services.get_status().account_status == "Guest" and hud.toast.contains("not configured"), "Unconfigured sign-in cannot fake account")
	hud.back()
	hud.handle_menu_role("test_ads")
	hud.handle_menu_role("test_request")
	expect(not scene.services.get_status().test_busy, "Unconfigured test ads cannot become live request")
	hud.back()

	check_training()
	await check_layout()
	scene.sound.stream_player.stop()
	scene.sound.stream_player.stream = null
	scene.queue_free()
	await process_frame
	await process_frame
	DirAccess.remove_absolute(TEST_SAVE)
	print("%s: %d campaign scene/input/layout checks (%d failures). Headless only; no screenshot or physical-device verification." % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)

func check_training() -> void:
	var progress_before: Dictionary = scene.profile.data.duplicate(true)
	hud.handle_menu_role("guide")
	hit(hud.start_rect(), "practice", "Guide starts real guided practice")
	hud.handle_menu_role("practice")
	expect(scene.play_mode == "training" and scene.training_step == 0 and scene.model.state == "playing", "Guided practice begins first lesson")
	for _i in range(121):
		hud.joystick = Vector2.RIGHT
		scene._physics_process(Battle.STEP)
	expect(scene.training_step == 1, "Two seconds steering completes first lesson")
	scene.model.time = 120.0
	scene.model.player_health = .001
	scene.model.rival_health = .001
	scene._physics_process(Battle.STEP)
	expect(scene.model.state == "playing" and scene.model.time < 111 and scene.model.player_health > 99, "Practice prevents death and timeout")
	scene.toggle_pause()
	hud.handle_menu_role("home")
	hud.handle_menu_role("guide")
	hud.handle_menu_role("practice")
	expect(scene.training_step == 0 and scene.training_progress == 0 and not scene.paused, "Restart resets practice lessons and pause state")
	var easing := false
	for _tick in range(7200):
		if scene.training_step == 0:
			hud.joystick = Vector2.RIGHT
		elif scene.training_step == 1:
			if scene.model.player_tension > .78:
				easing = true
			if scene.model.player_tension < .43:
				easing = false
			var target := Vector2(5.0 + sin(scene.model.time * 1.6) * 3.0, 20.0)
			var difference: Vector2 = target - Vector2(scene.model.player.x, scene.model.player.y)
			hud.joystick = Vector2(difference.x, -difference.y).limit_length(1.0)
			hud.pull_held = scene.model.contact and not easing
			hud.release_held = easing
		else:
			hud.joystick = Vector2.ZERO
			hud.pull_held = false
			hud.release_held = true
		scene._physics_process(Battle.STEP)
		if scene.model.state == "finished":
			break
	expect(scene.training_step == 3 and scene.model.state == "finished" and scene.model.result_reason == "training", "Steer, actual contact-cut, and ease complete all lessons")
	expect(scene.profile.data == progress_before, "Practice grants no stats, medals, titles, or cosmetic rewards")
	for _i in range(4):
		scene._physics_process(Battle.STEP)
	expect(scene.profile.data == progress_before, "Repeated practice completion cannot grant rewards")
	hud.activate_primary()
	expect(scene.model.state == "playing" and scene.play_mode == "campaign" and scene.active_encounter.index == 0, "Practice completion starts first campaign rival")
	scene.return_home()

func check_layout() -> void:
	var probe := MeasuringHud.new()
	probe.profile = Profile.new()
	probe.campaign = Campaign.new(probe.profile)
	probe.model = Battle.new()
	probe.services = scene.services
	root.add_child(probe)
	await process_frame
	probe.set_process(false)
	for dimensions in [Vector2(1280, 720), Vector2(1920, 1080), Vector2(1024, 768), Vector2(2340, 1080), Vector2(720, 1280)]:
		probe.size = dimensions
		probe._process(0)
		expect(probe.ui_size.x >= 1279 and probe.ui_size.y >= 719, "Canvas minimum logical extent at " + str(dimensions))
		for rect in [probe.start_rect(), probe.back_rect(), probe.pull_rect(), probe.release_rect(), probe.stage_rect(2), probe.chapter_rect(3)]:
			expect(Rect2(Vector2.ZERO, probe.ui_size).encloses(rect), "Interactive geometry remains on screen at " + str(dimensions))
	probe.ui_size = Vector2(1280, 720)
	for panel_name in ["settings", "wardrobe", "privacy", "account", "test_ads", "campaign", "briefing", "tournament", "quick", "guide"]:
		probe.panel = panel_name
		var variations := 12 if panel_name == "briefing" else (4 if panel_name == "campaign" else 1)
		for index in range(variations):
			probe.selected_stage = index
			probe.selected_chapter = index if panel_name == "campaign" else 0
			probe.text_items.clear()
			probe.button_items.clear()
			probe.draw_subpanel()
			for item in probe.text_items:
				var rect: Rect2 = item.rect
				expect(rect.position.x >= 311 and rect.end.x <= 969, "Panel text fits " + panel_name + ": " + str(item.text))
			for item in probe.button_items:
				expect(item.width <= item.rect.size.x - 12, "Button text fits " + panel_name + ": " + str(item.text))
	probe.queue_free()
	await process_frame
