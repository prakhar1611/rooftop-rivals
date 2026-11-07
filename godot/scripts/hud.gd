extends Control

signal start_requested
signal pause_requested
signal home_requested
signal settings_changed
signal account_requested
signal erase_requested
signal campaign_requested(index: int)
signal tournament_requested
signal practice_requested
signal quick_requested
signal continue_requested

var model: RefCounted
var profile: RefCounted
var services: Node
var campaign: RefCounted
var active_encounter := {}
var match_summary := {}
var play_mode := "quick"
var training_text := ""
var selected_chapter := 0
var selected_stage := 0
var panel := ""
var toast := ""
var toast_time := 0.0
var ui_offset := Vector2.ZERO
var erase_confirm := false
var paused := false
var joystick := Vector2.ZERO
var pull_held := false
var release_held := false
var touches := {}
var mouse_role := ""
var font: Font = ThemeDB.fallback_font
var scale_ui := 1.0
var ui_size := Vector2(1280, 720)
var ink := Color("142f36")
var cream := Color("fff3dc")
var teal := Color("30d0bd")
var amber := Color("ffc268")

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(_dt: float) -> void:
	toast_time = maxf(0, toast_time - _dt)
	var safe_size := size
	ui_offset = Vector2.ZERO
	if OS.has_feature("android"):
		var safe := DisplayServer.get_display_safe_area()
		if safe.size.x > 0 and safe.size.y > 0:
			var logical_safe := resolve_safe_area(Rect2(safe), get_screen_transform())
			ui_offset = logical_safe.position
			safe_size = logical_safe.size
	scale_ui = minf(safe_size.x / 1280.0, safe_size.y / 720.0)
	scale_ui = maxf(scale_ui, 0.1)
	ui_size = safe_size / scale_ui
	queue_redraw()

func resolve_safe_area(screen_rect: Rect2, screen_transform: Transform2D) -> Rect2:
	var logical: Rect2 = screen_transform.affine_inverse() * screen_rect
	var clipped := logical.intersection(Rect2(Vector2.ZERO, size))
	return clipped if clipped.has_area() else Rect2(Vector2.ZERO, size)

func joystick_center() -> Vector2:
	return Vector2(ui_size.x - 130 if is_left_handed() else 130, ui_size.y - 125)

func pull_rect() -> Rect2:
	return Rect2(40 if is_left_handed() else ui_size.x - 230, ui_size.y - 172, 190, 88)

func release_rect() -> Rect2:
	return Rect2(40 if is_left_handed() else ui_size.x - 230, ui_size.y - 72, 190, 48)

func start_rect() -> Rect2:
	return Rect2(ui_size.x / 2 - 160, ui_size.y / 2 + 126, 320, 64)

func clear_input() -> void:
	joystick = Vector2.ZERO
	pull_held = false
	release_held = false
	touches.clear()
	mouse_role = ""

func pick_role(point: Vector2) -> String:
	if model == null:
		return ""
	if model.state != "playing" or paused:
		return menu_role(point)
	if Rect2(ui_size.x - 78, 22, 52, 52).has_point(point):
		return "pause"
	if point.distance_to(joystick_center()) < 108:
		return "steer"
	if pull_rect().has_point(point):
		return "pull"
	if release_rect().has_point(point):
		return "release"
	return ""

func update_role(role: String, position_ui: Vector2, pressed: bool) -> void:
	if role == "steer":
		joystick = ((position_ui - joystick_center()) / 72.0).limit_length(1.0) if pressed else Vector2.ZERO
	elif role == "pull":
		pull_held = pressed
	elif role == "release":
		release_held = pressed
	elif pressed and role not in ["", "pause", "start"]:
		handle_menu_role(role)
	elif role == "start" and pressed:
		clear_input()
		activate_primary()
	elif role == "pause" and pressed:
		clear_input()
		pause_requested.emit()

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var p: Vector2 = (event.position - ui_offset) / scale_ui
		if event.pressed:
			var role := pick_role(p)
			if role == "steer" and "steer" in touches.values():
				role = ""
			touches[event.index] = role
			update_role(role, p, true)
		else:
			var role: String = touches.get(event.index, "")
			touches.erase(event.index)
			if not role in touches.values():
				update_role(role, p, false)
	elif event is InputEventScreenDrag:
		if touches.get(event.index, "") == "steer":
			update_role("steer", (event.position - ui_offset) / scale_ui, true)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = (event.position - ui_offset) / scale_ui
		if event.pressed:
			mouse_role = pick_role(p)
			update_role(mouse_role, p, true)
		else:
			update_role(mouse_role, p, false)
			mouse_role = ""
	elif event is InputEventMouseMotion and mouse_role == "steer":
		update_role("steer", (event.position - ui_offset) / scale_ui, true)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ENTER, KEY_R] and panel == "" and (model.state != "playing" or paused):
			clear_input()
			activate_primary()
		elif event.keycode in [KEY_ESCAPE, KEY_P]:
			back()

func card(rect: Rect2, color: Color, radius: int = 18) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	draw_style_box(style, rect)

func label_at(text_value: String, position_ui: Vector2, font_size: int, color: Color = cream) -> void:
	draw_string(font, position_ui, text_value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func center_text(text_value: String, y: float, font_size: int, color: Color = cream) -> void:
	var width := font.get_string_size(text_value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	label_at(text_value, Vector2((ui_size.x - width) / 2.0, y), font_size, color)

func bar(rect: Rect2, ratio: float, color: Color) -> void:
	card(rect, Color(1, 1, 1, 0.12), 5)
	if ratio > 0.0:
		card(Rect2(rect.position, Vector2(rect.size.x * clampf(ratio, 0, 1), rect.size.y)), color, 5)

func _draw() -> void:
	if model == null:
		return
	draw_set_transform(ui_offset, 0.0, Vector2.ONE * scale_ui)
	var w := ui_size.x
	var h := ui_size.y
	card(Rect2(24, 22, 312, 120), Color(0.06, 0.17, 0.20, 0.92))
	label_at("ROOFTOP RIVALS", Vector2(42, 50), 18, amber)
	label_at("YOU", Vector2(42, 78), 13, teal)
	bar(Rect2(90, 66, 214, 12), model.player_health / 100.0, teal)
	label_at("RIVAL", Vector2(42, 112), 13, Color("ff8d79"))
	bar(Rect2(90, 100, 214, 12), model.rival_health / 100.0, Color("ff8d79"))
	card(Rect2(w - 285, 22, 202, 94), Color(0.06, 0.17, 0.20, 0.90))
	var seconds: int = maxi(0, ceili(120.0 - model.time))
	label_at("PRACTICE  /  NO TIMER" if play_mode == "training" else "%d:%02d    %s" % [seconds / 60, seconds % 60, "CITY CUP" if play_mode == "tournament" else ("CAMPAIGN" if play_mode == "campaign" else "QUICK DUEL")], Vector2(w - 268, 50), 14)
	label_at("WIND  %s  %.1f" % ["LEFT" if model.wind.x < 0 else "RIGHT", absf(model.wind.x)], Vector2(w - 268, 82), 15, amber)
	card(Rect2(w - 68, 22, 42, 42), ink, 12)
	label_at("II", Vector2(w - 61, 56), 23)
	center_text("%04d  /  x%d" % [model.score, maxi(1, model.combo)], 55, 22, cream)
	if model.state == "playing" and not paused:
		var tension: float = model.player_tension
		var tension_color := Color("ff706b") if tension > 0.82 else teal
		card(Rect2(w / 2 - 192, h - 104, 384, 78), Color(0.06, 0.17, 0.20, 0.90))
		label_at("STRING TENSION", Vector2(w / 2 - 174, h - 77), 13, cream)
		label_at("%d%%" % (tension * 100), Vector2(w / 2 + 122, h - 77), 13, tension_color)
		draw_rect(Rect2(w / 2 - 174 + 348 * .4, h - 66, 348 * .42, 22), Color(.15, .8, .62, .25))
		bar(Rect2(w / 2 - 174, h - 61, 348, 12), tension, tension_color)
		draw_line(Vector2(w / 2 - 174 + 348 * .4, h - 64), Vector2(w / 2 - 174 + 348 * .4, h - 45), cream, 1.0)
		draw_line(Vector2(w / 2 - 174 + 348 * .82, h - 64), Vector2(w / 2 - 174 + 348 * .82, h - 45), cream, 1.0)
		var hint: String = training_text if play_mode == "training" else model.feedback
		center_text(hint, h - 129, 17, amber if model.contact else cream)
		center_text(str(active_encounter.get("rival", "Rival")) + "  /  " + model.rival_intent, 87, 14, cream)
		if model.wind_warning or model.gust_active:
			center_text("GUST INCOMING - EASE YOUR LINE" if model.wind_warning else "GUST - STEER INTO THE WIND", 117, 16, amber)
		if model.contact:
			var leverage: float = model.advantage
			center_text("POSITION EDGE: " + ("YOU" if leverage > .1 else ("RIVAL" if leverage < -.1 else "EVEN")), h - 154, 13, teal if leverage > 0 else amber)
		var joy := joystick_center()
		draw_circle(joy, 84, Color(0.06, 0.17, 0.20, 0.65))
		draw_arc(joy, 72, 0, TAU, 60, Color(1, 1, 1, 0.25), 2, true)
		draw_line(joy - Vector2(44, 0), joy + Vector2(44, 0), Color(1, 1, 1, 0.2), 1)
		draw_line(joy - Vector2(0, 44), joy + Vector2(0, 44), Color(1, 1, 1, 0.2), 1)
		draw_circle(joy + joystick * 57.0, 27, teal)
		label_at("STEER", joy + Vector2(-26, 112), 13)
		card(pull_rect(), amber.lightened(.15) if pull_held else amber)
		label_at("PULL / CUT", pull_rect().position + Vector2(26, 40), 23, ink)
		label_at("HOLD   [SPACE]", pull_rect().position + Vector2(37, 66), 13, ink)
		card(release_rect(), teal if release_held else ink, 13)
		label_at("RELEASE  [SHIFT]", release_rect().position + Vector2(22, 29), 16, ink if release_held else cream)
		label_at("ARROWS / WASD TO STEER", Vector2(26, h - 14), 11, Color(1, 1, 1, 0.7))
	else:
		draw_menu()
	if toast_time > 0.0:
		var lines := wrap_notice(toast)
		card(Rect2(w / 2 - 380, 155, 760, 30 + lines.size() * 22), ink)
		for i in range(lines.size()):
			center_text(lines[i], 184 + i * 22, 17, amber)

func is_left_handed() -> bool:
	return profile != null and profile.data.left_handed

func notify_user(message: String) -> void:
	toast = message.replace("\n", " ").left(260)
	toast_time = 7.0 if toast.length() > 90 else 4.0

func wrap_notice(message: String) -> Array[String]:
	var lines: Array[String] = []
	var line := ""
	for word in message.split(" ", false):
		var candidate := word if line.is_empty() else line + " " + word
		if font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x > 720 and not line.is_empty():
			lines.append(line)
			line = word
		else:
			line = candidate
	if not line.is_empty():
		lines.append(line)
	return lines

func menu_button_rect(column: int, row: int) -> Rect2:
	return Rect2(ui_size.x / 2 - 300 + column * 205, ui_size.y / 2 - 28 + row * 62, 190, 50)

func back_rect() -> Rect2:
	return Rect2(ui_size.x / 2 - 300, ui_size.y / 2 + 218, 190, 50)

func menu_role(point: Vector2) -> String:
	if panel != "":
		if back_rect().has_point(point):
			return "back"
		if panel in ["campaign", "briefing", "tournament", "guide", "quick"]:
			return campaign_menu_role(point)
		if panel == "settings":
			var toggles := ["sound", "haptics", "reduced_motion", "left_handed"]
			for i in range(4):
				if Rect2(ui_size.x / 2 - 300, ui_size.y / 2 - 115 + i * 62, 600, 50).has_point(point):
					return "toggle_" + toggles[i]
		elif panel == "wardrobe":
			for i in range(6):
				if menu_button_rect(i % 3, i / 3).has_point(point):
					return "skin_" + str(i)
		elif panel == "privacy":
			if Rect2(ui_size.x / 2 + 85, ui_size.y / 2 + 218, 215, 50).has_point(point):
				return "erase"
			if menu_button_rect(0, 2).has_point(point):
				return "test_ads"
			if menu_button_rect(2, 2).has_point(point):
				return "google_privacy"
		elif panel == "account":
			if start_rect().has_point(point):
				return "account_login"
			if Rect2(ui_size.x / 2 + 85, ui_size.y / 2 + 218, 215, 50).has_point(point):
				return "account_logout"
		elif panel == "test_ads":
			if Rect2(ui_size.x / 2 - 300, ui_size.y / 2 - 30, 600, 48).has_point(point):
				return "test_adult"
			if Rect2(ui_size.x / 2 - 300, ui_size.y / 2 + 30, 600, 48).has_point(point):
				return "test_opt_in"
			if start_rect().has_point(point):
				return "test_request"
			if Rect2(ui_size.x / 2 + 85, ui_size.y / 2 + 218, 215, 50).has_point(point):
				return "test_revoke"
		return ""
	if start_rect().has_point(point):
		return "start"
	var roles := ["settings", "wardrobe", "privacy"]
	for i in range(3):
		if Rect2(ui_size.x / 2 - 300 + i * 205, ui_size.y / 2 + 218, 190, 50).has_point(point):
			return roles[i]
	if Rect2(ui_size.x / 2 + 100, ui_size.y / 2 - 248, 200, 40).has_point(point):
		return "account"
	if paused:
		if Rect2(ui_size.x / 2 - 100, ui_size.y / 2 + 62, 200, 45).has_point(point):
			return "home"
	elif model.state == "ready":
		for i in range(3):
			if Rect2(ui_size.x / 2 - 300 + i * 205, ui_size.y / 2 - 64, 190, 85).has_point(point):
				return ["campaign", "tournament", "quick"][i]
		if Rect2(ui_size.x / 2 - 100, ui_size.y / 2 + 53, 200, 45).has_point(point):
			return "guide"
	elif model.state == "finished":
		if Rect2(ui_size.x / 2 - 100, ui_size.y / 2 + 62, 200, 45).has_point(point):
			return "home"
	return ""

func handle_menu_role(role: String) -> void:
	clear_input()
	if role in ["settings", "wardrobe", "privacy", "account", "test_ads", "campaign", "tournament", "quick", "guide"]:
		panel = role
		erase_confirm = false
	elif role == "back":
		panel = "campaign" if panel == "briefing" else ""
		erase_confirm = false
	elif role.begins_with("chapter_"):
		selected_chapter = clampi(int(role.trim_prefix("chapter_")), 0, 3)
	elif role.begins_with("stage_"):
		selected_stage = int(role.trim_prefix("stage_"))
		if campaign.is_stage_unlocked(selected_stage):
			panel = "briefing"
		else:
			notify_user("Win the previous rooftop to meet this rival.")
	elif role == "fly_stage":
		campaign_requested.emit(selected_stage)
	elif role == "fly_tournament":
		tournament_requested.emit()
	elif role == "practice":
		practice_requested.emit()
	elif role == "fly_quick":
		quick_requested.emit()
	elif role == "home":
		panel = ""
		home_requested.emit()
	elif role.begins_with("toggle_") and profile != null:
		var key := role.trim_prefix("toggle_")
		profile.data[key] = not profile.data[key]
		settings_changed.emit()
	elif role.begins_with("difficulty_") and profile != null:
		profile.data.difficulty = int(role.trim_prefix("difficulty_"))
		settings_changed.emit()
	elif role.begins_with("skin_") and profile != null:
		var index := int(role.trim_prefix("skin_"))
		if profile.skin_unlocked(index):
			profile.data.skin = index
			settings_changed.emit()
		else:
			notify_user(skin_requirement(index))
	elif role == "account_login":
		if services != null and services.get_status().login_pending:
			services.cancel_login()
		else:
			account_requested.emit()
	elif role == "account_logout" and services != null:
		services.clear_local_account()
	elif role == "test_adult" and services != null:
		services.set_age_eligibility("unknown" if services.get_status().age_eligibility == "adult" else "adult")
	elif role == "test_opt_in" and services != null:
		services.set_test_ad_opt_in(not services.get_status().test_ad_opt_in)
	elif role == "test_request" and services != null:
		if services.get_status().test_busy:
			services.cancel_test_rewarded_ad()
		else:
			services.request_test_rewarded_ad()
	elif role == "test_revoke" and services != null:
		services.set_test_ad_opt_in(false)
		services.set_age_eligibility("unknown")
		notify_user("New test requests are disabled. Use Google privacy choices for provider data.")
	elif role == "google_privacy" and services != null:
		services.show_privacy_options()
	elif role == "erase":
		if erase_confirm:
			erase_requested.emit()
			erase_confirm = false
		else:
			erase_confirm = true
			notify_user("Tap CONFIRM ERASE to permanently reset local progress.")

func back() -> void:
	clear_input()
	if panel != "":
		panel = "campaign" if panel == "briefing" else ""
		erase_confirm = false
	elif model.state == "playing":
		pause_requested.emit()
	elif model.state == "finished":
		home_requested.emit()

func button(rect: Rect2, text_value: String, selected: bool = false) -> void:
	card(rect, amber if selected else Color("29474e"), 12)
	var text_size := 17
	while text_size > 12 and font.get_string_size(text_value, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x > rect.size.x - 18:
		text_size -= 1
	var width := font.get_string_size(text_value, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x
	label_at(text_value, rect.position + Vector2((rect.size.x - width) / 2, 32), text_size, ink if selected else cream)

func activate_primary() -> void:
	if paused:
		start_requested.emit()
	elif model.state == "finished":
		if play_mode == "training":
			campaign_requested.emit(0)
		elif play_mode == "quick":
			quick_requested.emit()
		else:
			continue_requested.emit()
	elif campaign != null:
		selected_stage = campaign.next_stage_index()
		selected_chapter = selected_stage / 3
		panel = "briefing"
	else:
		start_requested.emit()

func draw_menu() -> void:
	var w := ui_size.x
	var h := ui_size.y
	draw_rect(Rect2(Vector2.ZERO, ui_size), Color(0.03, 0.10, 0.13, 0.55))
	card(Rect2(w / 2 - 345, h / 2 - 285, 690, 575), Color(0.06, 0.17, 0.20, 0.98), 28)
	if panel != "":
		draw_subpanel()
		return
	label_at("OFFLINE ROOFTOP LEAGUE", Vector2(w / 2 - 300, h / 2 - 223), 13, teal)
	button(Rect2(w / 2 + 100, h / 2 - 248, 200, 40), "GUEST / ACCOUNT")
	var title := "ROOFTOP RIVALS"
	var subtitle := "One neighborhood. A whole sky to win."
	if paused:
		title = "TAKE A BREATHER"
		subtitle = "Your duel is paused."
	elif model.state == "finished":
		title = "KAI PO CHE!" if model.result == "win" else ("A CLOSE DRAW" if model.result == "draw" else "FLY ANOTHER DAY")
		subtitle = "Score %d  /  Best combo x%d  /  String %d%%" % [model.score, model.best_combo, model.player_health]
	center_text(title, h / 2 - 153, 36, amber)
	center_text(subtitle, h / 2 - 116, 20)
	if model.state == "finished":
		var reasons := {"training": "You can steer, cut and ease. Now meet your first rival.","overstrain": "Your line broke under strain. Ease earlier next time.", "player_string_cut": "Your rival found the angle. Climb, sweep, then pull.", "rival_string_cut": "A clean cut. This rooftop is yours.", "time_health": "Time is up. The stronger remaining string wins.", "time_draw": "Time is up. Two strings, equally strong.", "double_cut": "Both strings broke at once."}
		center_text(reasons.get(model.result_reason, "A fresh wind. Another chance."), h / 2 - 67, 17)
		var progress := "Quick duel complete. Try a campaign rival next."
		if play_mode == "training":
			progress = "PRACTICE COMPLETE. No match stats or rewards added."
		elif play_mode == "campaign":
			progress = "%d / 3 medals earned  |  Rooftop best: %d / 3" % [match_summary.get("medals", 0), match_summary.get("best_medals", 0)]
		elif play_mode == "tournament":
			progress = "CITY CUP CHAMPION!" if match_summary.get("tournament_champion", false) else ("Round won. Your bracket is saved." if match_summary.get("tournament_advanced", false) else "Cup ended. A new bracket awaits.")
		center_text(progress, h / 2 - 22, 19, teal)
		var rewards: Array = match_summary.get("rewards", [])
		if not rewards.is_empty():
			center_text("New kite unlocked in your collection!", h / 2 + 22, 17, amber)
		button(Rect2(w / 2 - 100, h / 2 + 62, 200, 45), "BACK TO ROOFTOPS")
	elif paused:
		center_text("Cross lines. Gain height. Pull in the green zone.", h / 2 - 67, 18)
		center_text("Touch controls or WASD / arrows + Space + Shift", h / 2 - 13, 16, teal)
		button(Rect2(w / 2 - 100, h / 2 + 62, 200, 45), "LEAVE DUEL")
	else:
		for i in range(3):
			var r := Rect2(w / 2 - 300 + i * 205, h / 2 - 64, 190, 85)
			button(r, ["CAMPAIGN", "CITY CUP", "QUICK DUEL"][i], i == 0)
			label_at(["12 rival rooftops", "3-round tournament", "Pick your difficulty"][i], r.position + Vector2(16, 62), 13, ink if i == 0 else teal)
		button(Rect2(w / 2 - 100, h / 2 + 53, 200, 45), "HOW TO FLY")
	var primary := "CONTINUE CAMPAIGN"
	if paused:
		primary = "RESUME"
	elif model.state == "finished":
		primary = "FLY AGAIN" if play_mode == "quick" else ("NEXT ROOFTOP" if play_mode == "campaign" and model.result == "win" else "RETRY ROOFTOP")
		if play_mode == "training":
			primary = "START THE CAMPAIGN"
		if play_mode == "campaign" and int(active_encounter.get("index", 0)) == 11 and model.result == "win":
			primary = "REPLAY THE FINAL"
		if play_mode == "tournament":
			primary = "NEXT CUP ROUND" if campaign.has_active_tournament() else "RETURN HOME"
	button(start_rect(), primary, true)
	for i in range(3):
		button(Rect2(w / 2 - 300 + i * 205, h / 2 + 218, 190, 50), ["SETTINGS", "KITE COLLECTION", "PRIVACY"][i])
	center_text("0.10.0 CAMPAIGN PREVIEW  /  SKILL WINS. NO PAY-TO-WIN.", h / 2 + 282, 11, Color("9cb6b4"))

func draw_subpanel() -> void:
	var w := ui_size.x
	var h := ui_size.y
	if panel in ["campaign", "briefing", "tournament", "guide", "quick"]:
		draw_campaign_panel()
		return
	center_text({"settings": "MAKE IT YOURS", "wardrobe": "KITE COLLECTION", "privacy": "YOUR PLAY, YOUR DATA", "account": "OPTIONAL GOOGLE SIGN-IN", "test_ads": "GOOGLE TEST ADS"}.get(panel, "SETTINGS"), h / 2 - 220, 30, amber)
	button(back_rect(), "BACK")
	if panel == "settings":
		var keys := ["sound", "haptics", "reduced_motion", "left_handed"]
		var labels := ["Sound effects", "Haptics (supported phones)", "Reduce decorative motion", "Left-handed controls"]
		for i in range(4):
			var enabled: bool = profile != null and profile.data[keys[i]]
			button(Rect2(w / 2 - 300, h / 2 - 115 + i * 62, 600, 50), labels[i] + "    " + ("ON" if enabled else "OFF"), enabled)
		center_text("Settings are saved only on this device.", h / 2 + 165, 16, teal)
	elif panel == "wardrobe":
		center_text("Earn colours through skill. No purchase needed.", h / 2 - 135, 18)
		var names := ["JADE", "SAFFRON", "INDIGO", "ROSE", "SKY BLUE", "CHAMPION GOLD"]
		for i in range(6):
			var unlocked: bool = profile != null and profile.skin_unlocked(i)
			button(menu_button_rect(i % 3, i / 3), names[i] if unlocked else "LOCKED: " + names[i], profile != null and profile.data.skin == i)
		center_text("1 win / 5 wins / First chapter / Third chapter / Cup title", h / 2 + 135, 15, teal)
		center_text("Every kite has identical gameplay. Skill wins.", h / 2 + 175, 17, teal)
	elif panel == "privacy":
		var lines := ["Guest gameplay works offline. Google services are optional.", "Google may receive device/ad or account data if used.", "Scores and settings stay here. No game-owned analytics.", "This preview has no live ads, purchases or cloud saves.", "TEST ads need adult eligibility and a separate opt-in."]
		for i in range(lines.size()):
			center_text(lines[i], h / 2 - 147 + i * 40, 18, cream)
		button(menu_button_rect(0, 2), "SDK TEST ADS")
		button(menu_button_rect(2, 2), "GOOGLE PRIVACY")
		center_text("Never fly real kites near roads or electrical lines.", h / 2 + 185, 16, teal)
		button(Rect2(w / 2 + 85, h / 2 + 218, 215, 50), "CONFIRM ERASE" if erase_confirm else "ERASE PROGRESS")
	elif panel == "account":
		var status: Dictionary = services.get_status() if services != null else {}
		center_text("Guest play is always available.", h / 2 - 125, 22, teal)
		center_text("Google sign-in is available." if status.get("account_available", false) else "Google OAuth configuration is not supplied yet.", h / 2 - 65, 18)
		center_text("Use Google's secure chooser. Never enter a password here.", h / 2 - 20, 18)
		center_text("Device session only. Cloud saves are not connected.", h / 2 + 25, 18)
		center_text("Status: " + str(status.get("account_status", "Guest")), h / 2 + 75, 18, teal)
		button(start_rect(), "CANCEL SIGN-IN" if status.get("login_pending", false) else "SIGN IN WITH GOOGLE")
		button(Rect2(w / 2 + 85, h / 2 + 218, 215, 50), "SIGN OUT")
	elif panel == "test_ads":
		var status: Dictionary = services.get_status() if services != null else {}
		center_text("Official Google sample ad unit. Demo rewards only.", h / 2 - 155, 18)
		center_text("Google may receive device and ad-request data.", h / 2 - 115, 18)
		center_text("No saved game reward. Adult testing only, this session.", h / 2 - 75, 17, teal)
		var adult: bool = status.get("age_eligibility", "unknown") == "adult"
		var opted: bool = status.get("test_ad_opt_in", false)
		button(Rect2(w / 2 - 300, h / 2 - 30, 600, 48), "I AM 18 OR OLDER    " + ("YES" if adult else "NOT SET"), adult)
		button(Rect2(w / 2 - 300, h / 2 + 30, 600, 48), "ALLOW OPTIONAL GOOGLE TEST REQUESTS    " + ("ON" if opted else "OFF"), opted)
		var message := "Check eligibility and opt-in, then choose to load."
		if not status.get("test_ads_available", false):
			message = "Native Google SDK is unavailable on this build/device."
		elif model.state == "playing":
			message = "Finish or leave your duel before testing an ad."
		elif status.get("test_busy", false):
			message = "Google consent / test ad request is in progress."
		center_text(message, h / 2 + 108, 16, teal)
		button(start_rect(), "CANCEL REQUEST" if status.get("test_busy", false) else "LOAD A GOOGLE TEST AD")
		button(Rect2(w / 2 + 85, h / 2 + 218, 215, 50), "TURN TEST ADS OFF")

func skin_requirement(index: int) -> String:
	return ["Always unlocked.", "Win one duel to unlock Saffron.", "Win five duels to unlock Indigo.", "Complete the first campaign chapter to unlock Rose.", "Complete the third campaign chapter to unlock Sky Blue.", "Win a City Cup to unlock Champion Gold."][clampi(index, 0, 5)]

func chapter_rect(index: int) -> Rect2:
	return Rect2(ui_size.x / 2 - 300 + index * 152, ui_size.y / 2 - 165, 144, 44)

func stage_rect(index: int) -> Rect2:
	return Rect2(ui_size.x / 2 - 300, ui_size.y / 2 - 102 + index * 95, 600, 82)

func campaign_menu_role(point: Vector2) -> String:
	if panel == "campaign":
		for i in range(4):
			if chapter_rect(i).has_point(point):
				return "chapter_" + str(i)
		for i in range(3):
			if stage_rect(i).has_point(point):
				return "stage_" + str(selected_chapter * 3 + i)
	elif panel == "briefing" and start_rect().has_point(point):
		return "fly_stage"
	elif panel == "tournament" and start_rect().has_point(point):
		return "fly_tournament"
	elif panel == "quick":
		for i in range(3):
			if menu_button_rect(i, 1).has_point(point):
				return "difficulty_" + str(i)
		if start_rect().has_point(point):
			return "fly_quick"
	elif panel == "guide" and start_rect().has_point(point):
		return "practice"
	return ""

func draw_campaign_panel() -> void:
	var w := ui_size.x
	var h := ui_size.y
	button(back_rect(), "BACK")
	if panel == "campaign":
		center_text("THE NEIGHBORHOOD LEAGUE", h / 2 - 220, 29, amber)
		var chapter_names := ["AHMEDABAD", "JAIPUR", "LUCKNOW", "VARANASI"]
		for i in range(4):
			button(chapter_rect(i), chapter_names[i], selected_chapter == i)
		var stages: Array = campaign.get_stages()
		for i in range(3):
			var index := selected_chapter * 3 + i
			var stage: Dictionary = stages[index]
			var r := stage_rect(i)
			var unlocked: bool = campaign.is_stage_unlocked(index)
			card(r, Color("29474e") if unlocked else Color("1e343c"), 14)
			label_at("%02d   %s" % [index + 1, stage.rival], r.position + Vector2(18, 30), 21, cream if unlocked else Color("8aa09e"))
			label_at(str(stage.title), r.position + Vector2(18, 60), 15, teal)
			label_at("%d / 3 MEDALS" % campaign.stage_medals(index) if unlocked else "LOCKED", r.position + Vector2(445, 40), 14, amber)
		center_text("%d / 36 medals. Win each rooftop to open the next." % campaign.total_medals(), h / 2 + 197, 16, teal)
	elif panel == "briefing":
		var stage: Dictionary = campaign.get_stages()[selected_stage]
		center_text("ROOFTOP %02d  /  %s" % [selected_stage + 1, str(stage.style).to_upper()], h / 2 - 220, 23, teal)
		center_text(str(stage.rival), h / 2 - 162, 34, amber)
		center_text(str(stage.title), h / 2 - 124, 21)
		center_text(str(stage.weather), h / 2 - 82, 17, teal)
		var lines := wrap_notice(str(stage.tip))
		for i in range(lines.size()):
			center_text(lines[i], h / 2 - 40 + i * 25, 17)
		center_text("1 medal: win    +1: clean cuts %.1fs    +1: finish at %.0f%% line" % [stage.medal_clean_time, stage.medal_health], h / 2 + 59, 16, amber)
		center_text("Best: %d / 3 medals. Replays keep your best result." % campaign.stage_medals(selected_stage), h / 2 + 95, 16, teal)
		button(start_rect(), "CHALLENGE RIVAL", true)
	elif panel == "tournament":
		center_text("THE CITY CUP", h / 2 - 220, 34, amber)
		center_text("Three duels. One champion.", h / 2 - 151, 23)
		var active: bool = campaign.has_active_tournament()
		center_text("QUARTERFINAL  >  SEMIFINAL  >  FINAL", h / 2 - 98, 18, teal)
		center_text("Each round brings a fresh rival, wind and full string.", h / 2 - 50, 17)
		center_text("Win to advance. A loss or draw ends this cup.", h / 2 - 10, 17)
		center_text("Bracket progress saves between rounds, only here.", h / 2 + 30, 17)
		center_text("Titles: %d  |  Champion Gold kite awaits your first." % profile.data.tournament_titles, h / 2 + 78, 17, amber)
		button(start_rect(), "RESUME SAVED CUP" if active else "ENTER CITY CUP", true)
	elif panel == "quick":
		center_text("QUICK DUEL", h / 2 - 220, 34, amber)
		center_text("A fresh rival and wind on every rematch.", h / 2 - 140, 20)
		center_text("Practice freely. Campaign progress stays unchanged.", h / 2 - 95, 17)
		center_text("Breezy to learn. Expert to sharpen your timing.", h / 2 - 48, 17, teal)
		for i in range(3):
			button(menu_button_rect(i, 1), ["BREEZY", "ROOFTOP", "EXPERT"][i], profile.data.difficulty == i)
		button(start_rect(), "LET'S FLY", true)
	elif panel == "guide":
		center_text("FLY WITH INTENT", h / 2 - 220, 32, amber)
		var lines := ["1  STEER: move your kite across your rival's tether.", "2  POSITION: height and crossing angle give an edge.", "3  PULL: cut while crossed, in the marked green zone.", "4  RELEASE: ease the line before red or a gust.", "5  READ: a rival's next move is shown above the sky.", "6  WIN: cut their string, or keep more line at timeout."]
		for i in range(lines.size()):
			label_at(lines[i], Vector2(w / 2 - 298, h / 2 - 153 + i * 40), 17, teal if i % 2 == 0 else cream)
		button(start_rect(), "START GUIDED PRACTICE", true)
