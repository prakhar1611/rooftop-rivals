extends SceneTree

var checks := 0
var failures := 0
func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		push_error("FAIL: " + message)
		failures += 1

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	expect(scene.player_kite is Node3D and scene.camera is Camera3D, "Real 3D scene instantiated")
	expect(scene.city_meshes_after < scene.city_meshes_before / 3, "Static city material batches reduce mesh count")
	print("City batching: %d -> %d static mesh instances" % [scene.city_meshes_before, scene.city_meshes_after])
	expect(scene.model.state == "ready", "Launch overlay waits for user")
	scene.start_or_resume()
	expect(scene.model.state == "playing", "Start enters playing")
	var hud = scene.hud
	var safe: Rect2 = hud.resolve_safe_area(Rect2(150, 0, 1770, 1080), Transform2D(Vector2(1.5, 0), Vector2(0, 1.5), Vector2.ZERO))
	expect(is_equal_approx(safe.position.x, 100) and safe.end.x <= hud.size.x, "Physical notch safe area converts to logical canvas units")
	var press := InputEventScreenTouch.new()
	press.index = 1
	press.pressed = true
	press.position = (hud.joystick_center() + Vector2(50, 0)) * hud.scale_ui
	hud._input(press)
	expect(hud.joystick.x > .5, "Touch steers joystick")
	var pull := InputEventScreenTouch.new()
	pull.index = 2
	pull.pressed = true
	pull.position = hud.pull_rect().get_center() * hud.scale_ui
	hud._input(pull)
	expect(hud.pull_held and hud.joystick.x > .5, "Simultaneous steer plus pull touches")
	pull.pressed = false
	hud._input(pull)
	expect(not hud.pull_held and hud.joystick.x > .5, "Pull release preserves steering finger")
	press.pressed = false
	hud._input(press)
	expect(hud.joystick == Vector2.ZERO, "Joystick release clears steering")
	scene.toggle_pause()
	var time: float = scene.model.time
	scene._physics_process(1.0 / 60)
	expect(scene.paused and scene.model.time == time, "Pause stops simulation")
	scene.start_or_resume()
	expect(not scene.paused and scene.model.state == "playing", "Resume preserves round")
	scene.model.finish("win")
	scene.start_or_resume()
	expect(scene.model.player_health == 100 and scene.model.rival_health == 100 and scene.model.result == "", "Replay resets round")
	scene._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	expect(scene.paused and hud.joystick == Vector2.ZERO, "Focus loss pauses and clears input")
	hud.handle_menu_role("settings")
	expect(hud.panel == "settings" and scene.paused, "Settings do not resume match")
	var original: bool = scene.profile.data.left_handed
	hud.handle_menu_role("toggle_left_handed")
	expect(scene.profile.data.left_handed != original, "Control handedness toggle")
	expect((hud.joystick_center().x > hud.ui_size.x / 2) == scene.profile.data.left_handed, "Handedness changes joystick side")
	hud.back()
	expect(hud.panel == "" and scene.paused, "Back from settings preserves pause")
	hud.handle_menu_role("privacy")
	hud.back()
	expect(hud.panel == "" and scene.paused, "Back from privacy preserves pause")
	hud.handle_menu_role("account")
	hud.handle_menu_role("account_login")
	expect(hud.toast.contains("not configured") and scene.services.get_status().account_status == "Guest", "Unconfigured login stays honest and guest-only")
	hud.back()
	hud.handle_menu_role("test_ads")
	hud.handle_menu_role("test_adult")
	expect(scene.services.get_status().age_eligibility == "adult", "Test age declaration is explicit and local")
	hud.handle_menu_role("test_opt_in")
	expect(scene.services.get_status().test_ad_opt_in, "Test requests require separate local opt-in")
	hud.handle_menu_role("test_request")
	expect(not scene.services.get_status().test_busy and hud.toast.contains("unavailable"), "Missing native SDK cannot fake a test request")
	hud.handle_menu_role("test_revoke")
	expect(not scene.services.get_status().test_ad_opt_in and scene.services.get_status().age_eligibility == "unknown", "Test privacy revoke disables and clears eligibility")
	hud.back()
	scene.return_home()
	expect(scene.model.state == "ready" and not scene.paused and not hud.pull_held, "Leave duel returns home cleanly")
	hud.handle_menu_role("difficulty_2")
	scene.start_or_resume()
	expect(scene.model.difficulty == 2, "Chosen difficulty reaches match model")
	scene.profile.data.left_handed = original
	scene.profile.data.difficulty = 1
	scene.apply_settings()
	scene.return_home()
	for panel_name in ["", "settings", "wardrobe", "privacy", "account", "test_ads"]:
		hud.panel = panel_name
		hud.queue_redraw()
		await process_frame
		expect(hud.back_rect().end.y < hud.ui_size.y, "Panel controls fit native landscape viewport")
	hud.panel = ""
	scene.model.state = "finished"
	hud.back()
	expect(scene.model.state == "ready", "Back from result returns home")
	print("%s: %d scene/input checks (%d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	scene.sound.stream_player.stop()
	scene.sound.stream_player.stream = null
	await create_timer(.1).timeout
	scene.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures == 0 else 1)
