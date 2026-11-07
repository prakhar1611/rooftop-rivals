extends RefCounted
## Fixed-step, renderer-independent arcade kite simulation.
## All opponent decisions are deterministic local rules. No model/API/network use.
## Input and player_velocity use screen Y (negative is up); wind and rival_velocity
## use world Y (positive is up). Tension, cutting rules and gust load are symmetric.

const STEP := 1.0 / 60.0
const ROUND_LIMIT := 120.0
const PLAYER_ANCHOR := Vector3(-6.5, 4.4, 5.5)
const RIVAL_ANCHOR := Vector3(6.5, 4.4, 5.5)
const DIFFICULTIES := ["Breezy", "Rooftop", "Expert"]
const STYLES := ["sweeper", "patient", "pressurer", "dancer", "reader", "champion"]

var time := 0.0
var player := Vector3(-5.0, 18.0, -9.0)
var rival := Vector3(5.0, 19.0, -9.0)
var player_velocity := Vector2.ZERO
var rival_velocity := Vector2.ZERO
var player_health := 100.0
var rival_health := 100.0
var player_tension := 0.35
var rival_tension := 0.35
var wind := Vector2.ZERO
var contact := false
var clash_position := Vector3.ZERO
var state := "ready"
var result := ""
var opponent_state := "APPROACH"
var seed_value := 23
var last_player_damage := 0.0
var last_rival_damage := 0.0
var difficulty := 1
var opponent_style := "SWEEPER"
var result_reason := ""
var score := 0
var combo := 0
var best_combo := 0
var clean_cut_time := 0.0
var damage_dealt := 0.0
var damage_taken := 0.0
# Public tactical data, safe for HUDs and replay/test tools.
var encounter_id := "free_duel"
var feedback := "Cross the strings. Pull in the green tension zone."
var wind_warning := false
var gust_active := false
var advantage := 0.0 # [-1, 1]; positive means the player has better cutting leverage.
var crossing_angle := 0.0 # Degrees between tethers; narrow crossings cut slowly.
var rival_intent := "Sweeping across your line"
var wind_strength := 1.0
var gust_strength := 0.7
var gust_interval := 9.0
var gust_duration := 2.2
var gust_warning := 1.5
# Events clear each valid simulation step.
var events: Array[String] = []
var _score_fraction := 0.0
var _combo_clock := 0.0
var _combo_grace := 0.0
var _style_index := 0
var _phase := 0.0
var _gust_start := 6.0
var _gust_load := 0.0
var _ai_clock := 0.0
var _ai_aim := Vector2.ZERO
var _ai_pull := false
var _ai_release := false
var _ai_recovering := false
var _observed_player_velocity := Vector2.ZERO
var _telegraph_clock := 0.0
var _pull_age := 0.0
var _rival_pull_age := 0.0

func reset(match_seed: int = 23, difficulty_level: int = 1) -> void:
	difficulty = clampi(difficulty_level, 0, 2)
	# Keep legacy seed personalities for callers that do not configure encounters.
	_style_index = posmod(match_seed, 3)
	opponent_style = STYLES[_style_index].to_upper()
	_phase = float(posmod(match_seed, 97)) * 0.13
	score = 0
	combo = 0
	best_combo = 0
	clean_cut_time = 0.0
	damage_dealt = 0.0
	damage_taken = 0.0
	_score_fraction = 0.0
	_combo_clock = 0.0
	_combo_grace = 0.0
	events.clear()
	result_reason = ""
	clash_position = Vector3.ZERO
	time = 0.0
	player = Vector3(-5.0, 18.0, -9.0)
	rival = Vector3(5.0, 19.0, -9.0)
	player_velocity = Vector2.ZERO
	rival_velocity = Vector2.ZERO
	player_health = 100.0
	rival_health = 100.0
	player_tension = 0.35
	rival_tension = 0.35
	wind = Vector2.ZERO
	contact = false
	state = "playing"
	result = ""
	opponent_state = "APPROACH"
	seed_value = match_seed
	last_player_damage = 0.0
	last_rival_damage = 0.0
	encounter_id = "free_duel"
	wind_strength = 1.0
	gust_strength = 0.7
	gust_interval = 9.0
	gust_duration = 2.2
	gust_warning = 1.5
	_reset_tactics()

## Call after reset(), before the first step. Unknown keys are ignored.
## id: encounter identifier (String); style: one of STYLES, case-insensitive.
## wind_strength: 0..2.5, gust_strength: 0..2.5 (0 disables gusts).
## gust_interval: 5..18 seconds between starts; gust_duration: .8..3 seconds;
## gust_warning: .8..2.5 seconds of visible warning before every gust.
## Omitted/invalid values preserve defaults; values are bounded and finite.
## No equipment stats, health bonuses or progression multipliers are applied.
func configure_encounter(config: Dictionary) -> void:
	# A paused/ongoing match cannot be reconfigured to remove a coming hazard.
	if time != 0.0 or state != "playing":
		return
	if config.get("id") is String:
		encounter_id = config.id.left(96)
	if config.get("style") is String:
		var style: String = config.style.to_lower()
		var style_id := STYLES.find(style)
		if style_id >= 0:
			_style_index = style_id
			opponent_style = style.to_upper()
	wind_strength = _config_number(config, "wind_strength", wind_strength, 0.0, 2.5)
	gust_strength = _config_number(config, "gust_strength", gust_strength, 0.0, 2.5)
	gust_interval = _config_number(config, "gust_interval", gust_interval, 5.0, 18.0)
	gust_duration = _config_number(config, "gust_duration", gust_duration, 0.8, 3.0)
	gust_warning = _config_number(config, "gust_warning", gust_warning, 0.8, 2.5)
	# Always leave a calm gap, even for extreme valid configurations.
	gust_interval = maxf(gust_interval, gust_duration + gust_warning + 0.75)
	_reset_tactics()

func _config_number(config: Dictionary, key: String, fallback: float, low: float, high: float) -> float:
	var value: Variant = config.get(key, fallback)
	if not (value is float or value is int) or not is_finite(float(value)):
		return fallback
	return clampf(float(value), low, high)

func _reset_tactics() -> void:
	feedback = "Cross the strings. Pull in the green tension zone."
	wind_warning = false
	gust_active = false
	advantage = 0.0
	crossing_angle = 0.0
	_gust_start = 4.5 + float(posmod(seed_value, 17)) * 0.13 + gust_warning
	_gust_load = 0.0
	_ai_clock = 0.0
	_ai_aim = Vector2(rival.x, rival.y)
	_ai_pull = false
	_ai_release = false
	_ai_recovering = false
	_observed_player_velocity = Vector2.ZERO
	_telegraph_clock = 0.0
	_pull_age = 0.0
	_rival_pull_age = 0.0
	rival_intent = ["Sweeping across your line", "Waiting for a clean crossing", "Closing in for a long pull", "Circling to change the angle", "Watching your movement", "Sizing up your line"][_style_index]

func step(direction: Vector2, pulling: bool, releasing: bool, delta: float = STEP) -> void:
	if state != "playing" or not is_finite(delta) or delta <= 0.0:
		return
	events.clear()
	if not direction.is_finite():
		direction = Vector2.ZERO
	var health_before := player_health
	var rival_before := rival_health
	var was_contact := contact
	# Fixed STEP is normal play. Large debug/frame deltas cannot skip a warning.
	var dt := minf(minf(delta, 0.05), maxf(0.0, ROUND_LIMIT - time))
	time += dt
	_update_wind()
	var steer := direction.limit_length(1.0)
	_update_opponent(dt)
	var ai_direction := (_ai_aim - Vector2(rival.x, rival.y)).limit_length(1.0)
	var player_pulling := pulling and not releasing
	player_tension = update_tension(player_tension, player_pulling, releasing, steer.length(), dt)
	rival_tension = update_tension(rival_tension, _ai_pull, _ai_release, ai_direction.length(), dt)
	_pull_age = _pull_age + dt if player_pulling else 0.0
	_rival_pull_age = _rival_pull_age + dt if _ai_pull else 0.0
	var player_speed := 5.2 if player_pulling else 6.4
	var rival_speed := [3.4, 3.15, 4.0, 4.8, 4.25, 4.7][_style_index] as float
	rival_speed *= [0.82, 1.0, 1.12][difficulty] as float
	if _ai_pull:
		rival_speed *= 0.82
	player_velocity = player_velocity.lerp(steer * player_speed + Vector2(wind.x, -wind.y), minf(1.0, dt * 4.0))
	rival_velocity = rival_velocity.lerp(ai_direction * rival_speed + wind, minf(1.0, dt * 3.0))
	player += Vector3(player_velocity.x, -player_velocity.y, 0.0) * dt
	rival += Vector3(rival_velocity.x, rival_velocity.y, 0.0) * dt
	player.x = clampf(player.x, -14.0, 14.0)
	rival.x = clampf(rival.x, -14.0, 14.0)
	player.y = clampf(player.y, 10.0, 27.0)
	rival.y = clampf(rival.y, 10.0, 27.0)
	# Do not award cutting speed for movement stopped by an arena boundary.
	player_velocity = _stop_at_edge(player, player_velocity, true)
	rival_velocity = _stop_at_edge(rival, rival_velocity, false)
	player.z = -9.0 + sin(time * 0.5) * 0.6
	rival.z = player.z
	contact = strings_touch()
	_update_leverage()
	last_player_damage = 0.0
	last_rival_damage = 0.0
	if contact and not was_contact:
		events.append("clash")
	if contact:
		# Cutting angle and height work for both sides. Continuous held pulls lose
		# bite as the line locks; let go briefly and set up another controlled pass.
		var angle_bite := lerpf(0.60, 1.0, clampf(crossing_angle / 55.0, 0.0, 1.0))
		var player_force := cut_force(player_tension, player_pulling, player_velocity.length()) * _stroke_bite(_pull_age)
		var rival_force := cut_force(rival_tension, _ai_pull, rival_velocity.length()) * _stroke_bite(_rival_pull_age)
		player_force *= angle_bite * (1.0 + advantage * 0.65)
		rival_force *= angle_bite * (1.0 - advantage * 0.65)
		# Difficulty changes execution, not invisible string health/equipment.
		rival_force *= [0.70, 0.93, 1.0][difficulty] as float
		last_rival_damage = player_force * dt * (0.42 if _ai_release else 1.0)
		last_player_damage = rival_force * dt * (0.30 if releasing else 1.0)
		player_health -= last_player_damage
		rival_health -= last_rival_damage
	var player_overstrained := player_tension > 0.92
	if player_overstrained:
		player_health -= (player_tension - 0.92) * 120.0 * dt
	if rival_tension > 0.92:
		rival_health -= (rival_tension - 0.92) * 120.0 * dt
	player_health = clampf(player_health, 0.0, 100.0)
	rival_health = clampf(rival_health, 0.0, 100.0)
	damage_dealt += rival_before - rival_health
	damage_taken += health_before - player_health
	_score_cut(player_pulling, releasing, player_overstrained, dt)
	_update_feedback(releasing, player_pulling)
	if player_health <= 0.0 and rival_health <= 0.0:
		finish("draw", "double_cut")
	elif rival_health <= 0.0:
		finish("win", "rival_string_cut")
	elif player_health <= 0.0:
		finish("loss", "overstrain" if player_overstrained else "player_string_cut")
	elif time >= ROUND_LIMIT:
		if absf(player_health - rival_health) < 2.0:
			finish("draw", "time_draw")
		else:
			finish("win" if player_health > rival_health else "loss", "time_health")

func _update_wind() -> void:
	var was_warning := wind_warning
	var was_gust := gust_active
	var next_start := _gust_start
	if time >= _gust_start:
		var cycle := floorf((time - _gust_start) / gust_interval)
		next_start += cycle * gust_interval
		if time >= next_start + gust_duration:
			next_start += gust_interval
	var gust_elapsed := time - next_start
	gust_active = gust_strength > 0.0 and gust_elapsed >= 0.0 and gust_elapsed < gust_duration
	wind_warning = gust_strength > 0.0 and gust_elapsed < 0.0 and gust_elapsed >= -gust_warning
	var gust_shape := sin(clampf(gust_elapsed / gust_duration, 0.0, 1.0) * PI) if gust_active else 0.0
	var gust_number := floori((next_start - _gust_start) / gust_interval)
	var gust_sign := -1.0 if posmod(seed_value + gust_number, 2) == 0 else 1.0
	wind = Vector2(sin(time * 0.31 + _phase) * 0.95 + sin(time * 1.17 + _phase * 0.3) * 0.30, cos(time * 0.43 + _phase) * 0.30) * wind_strength
	wind += Vector2(gust_sign * 2.2, 0.50) * gust_shape * gust_strength
	_gust_load = gust_shape * gust_strength * 0.10
	if wind_warning and not was_warning:
		events.append("gust_warning")
	if gust_active and not was_gust:
		events.append("gust")

func _update_opponent(dt: float) -> void:
	_ai_clock -= dt
	_telegraph_clock = maxf(0.0, _telegraph_clock - dt)
	# Read only prior, visible movement. No access to this tick's player input.
	_observed_player_velocity = _observed_player_velocity.lerp(Vector2(player_velocity.x, -player_velocity.y), minf(1.0, dt * 1.8))
	if _ai_clock > 0.0:
		return
	_ai_clock = [0.32, 0.24, 0.16][difficulty] as float
	var cycle := fmod(time + _phase * 0.25, 6.4)
	var target := Vector2(player.x - 4.6, player.y)
	var wants_pull := contact
	var next_intent := "Sweeping across your line"
	match _style_index:
		0: # Generous lateral sweeps: readable starter, weak at holding high ground.
			target.y = player.y - 0.65 + sin(time * 0.65 + _phase) * 1.1
			target.x += sin(time * 0.65 + _phase) * 2.0
			wants_pull = contact and cycle < 4.1
			next_intent = "Sweeping low" if target.y < player.y else "Sweeping high"
		1: # Settles above the crossing, waits, then spends stored tension.
			target.y = player.y + (0.95 if wants_pull else 1.6)
			target.x += 1.1 if cycle > 3.8 else -0.8
			wants_pull = contact and cycle > 1.1 and cycle < 4.6
			next_intent = "Waiting above your line" if not wants_pull else "Preparing a patient cut"
		2: # Closes the gap and makes long attacks with obvious recovery windows.
			target.x -= 1.2
			target.y = player.y + sin(time * 0.8) * 0.9
			wants_pull = contact and cycle < 5.3
			next_intent = "Closing in for a long pull"
		3: # Alternates above/below, changes angle, cuts in short passing strokes.
			target.x += sin(time * 1.4 + _phase) * 2.5
			target.y = player.y + sin(time * 1.4 + _phase) * 1.7
			wants_pull = contact and fmod(time, 2.5) < 1.45
			next_intent = "Diving under your line" if target.y < player.y else "Climbing for a new angle"
		4: # Tracks delayed velocity and counters predictable low, fixed positions.
			target += _observed_player_velocity * 0.65
			target.y += 1.0
			wants_pull = contact and (player_tension > 0.66 or cycle < 3.6)
			next_intent = "Reading your next pass" if not wants_pull else "Setting up a counter-cut"
		5: # Combines high-ground pressure with measured strokes and recoveries.
			target += _observed_player_velocity * 0.40
			target.x -= 3.9 + sin(time * 1.8 + _phase) * 2.4
			target.y += 1.15 + sin(time * 1.1 + _phase) * 0.35
			wants_pull = contact and fmod(time, 2.8) < 2.3
			next_intent = "Taking the high crossing" if target.y > rival.y + 0.8 else "Preparing a precision stroke"
	# Hysteresis prevents instant pull/release chatter and creates useful openings.
	var release_at := [0.72, 0.78, 0.80][difficulty] as float
	if wind_warning:
		release_at -= 0.10 if _style_index >= 4 else 0.03
	if rival_tension >= release_at:
		_ai_recovering = true
	elif rival_tension <= 0.42:
		_ai_recovering = false
	_ai_release = _ai_recovering or (gust_active and rival_tension > 0.78)
	if _style_index >= 4 and not wants_pull and rival_tension > 0.48:
		_ai_release = true
	if _ai_release:
		wants_pull = false
		next_intent = "Letting line out: attack window"
	elif wants_pull and not _ai_pull:
		# Every new attacking stroke has a visible wind-up, including the champion.
		if _telegraph_clock <= 0.0 and opponent_state != "WIND UP":
			_telegraph_clock = 0.44 if difficulty == 0 else 0.28
			opponent_state = "WIND UP"
		wants_pull = _telegraph_clock <= 0.0
		if not wants_pull:
			next_intent = "Winding up: move or ease line"
	_ai_pull = wants_pull and not _ai_release
	if _ai_release:
		opponent_state = "COOL DOWN"
	elif _ai_pull:
		opponent_state = "CUT"
	elif _telegraph_clock <= 0.0:
		opponent_state = "APPROACH"
	rival_intent = next_intent
	_ai_aim = Vector2(clampf(target.x, -12.5, 12.5), clampf(target.y, 10.0, 27.0))

func _stop_at_edge(position: Vector3, velocity: Vector2, screen_y: bool) -> Vector2:
	if (position.x <= -14.0 and velocity.x < 0.0) or (position.x >= 14.0 and velocity.x > 0.0):
		velocity.x = 0.0
	var vertical := -velocity.y if screen_y else velocity.y
	if (position.y <= 10.0 and vertical < 0.0) or (position.y >= 27.0 and vertical > 0.0):
		velocity.y = 0.0
	return velocity

func _update_leverage() -> void:
	var player_line := (Vector2(player.x, player.y) - Vector2(PLAYER_ANCHOR.x, PLAYER_ANCHOR.y)).normalized()
	var rival_line := (Vector2(rival.x, rival.y) - Vector2(RIVAL_ANCHOR.x, RIVAL_ANCHOR.y)).normalized()
	crossing_angle = rad_to_deg(acos(clampf(player_line.dot(rival_line), -1.0, 1.0)))
	var player_motion := Vector2(player_velocity.x, -player_velocity.y)
	# Perpendicular movement saws across a tether; movement along it does not.
	var player_sweep := absf(player_motion.cross(player_line))
	var rival_sweep := absf(rival_velocity.cross(rival_line))
	var height_edge := clampf((player.y - rival.y) / 1.8, -1.0, 1.0)
	var sweep_edge := clampf((player_sweep - rival_sweep) / 5.5, -1.0, 1.0)
	advantage = clampf(height_edge * 0.70 + sweep_edge * 0.30, -1.0, 1.0)

func _stroke_bite(age: float) -> float:
	return lerpf(1.0, 0.45, clampf((age - 1.6) / 2.2, 0.0, 1.0))

func update_tension(value: float, pull: bool, release: bool, steering: float, dt: float) -> float:
	if release:
		value -= dt * 0.5
	elif pull:
		value += dt * (0.16 + steering * 0.045 + _gust_load)
	else:
		value = move_toward(value, 0.35, dt * 0.10)
	return clampf(value, 0.08, 1.0)

func cut_force(tension: float, pull: bool, speed: float) -> float:
	if not pull:
		return 0.0 # Idle/release can defend, never cut or farm wins/points.
	var sweet := 1.0 if tension >= 0.4 and tension <= 0.82 else 0.40
	return (8.0 + minf(speed, 7.0) * 1.2) * sweet

func _score_cut(pulling: bool, releasing: bool, overstrained: bool, dt: float) -> void:
	var clean_cut := contact and pulling and not releasing and player_tension >= 0.4 and player_tension <= 0.82 and last_rival_damage > 0.0
	if clean_cut:
		clean_cut_time += dt
		_combo_clock += dt
		_combo_grace = 1.2
		if combo == 0:
			combo = 1
		if _combo_clock >= 0.75:
			_combo_clock -= 0.75
			combo = mini(5, combo + 1)
			events.append("clean_cut")
		best_combo = maxi(best_combo, combo)
		_score_fraction += last_rival_damage * (10.0 + combo * 2.0)
		var points := int(_score_fraction)
		score += points
		_score_fraction -= points
	else:
		_combo_grace -= dt
		if _combo_grace <= 0.0 or overstrained:
			combo = 0
			_combo_clock = 0.0

func _update_feedback(releasing: bool, pulling: bool) -> void:
	if player_tension > 0.88:
		feedback = "Line near breaking. Release now!"
	elif wind_warning:
		feedback = "Gust coming. Ease line before it hits."
	elif gust_active and pulling:
		feedback = "Gust loading your line. Watch tension."
	elif not contact:
		feedback = "Move across the rival to cross strings."
	elif releasing:
		feedback = "Line eased. Reposition for your next cut."
	elif advantage < -0.25:
		feedback = "Rival has the angle. Climb or sweep sideways."
	elif _pull_age > 2.0:
		feedback = "Long pull losing bite. Ease, then strike again."
	elif player_tension < 0.4:
		feedback = "Line too loose. Pull into the green zone."
	elif advantage > 0.25:
		feedback = "Strong angle. Pull for a clean cut!"
	else:
		feedback = "Strings crossed. Short pulls, then ease."

func strings_touch() -> bool:
	var points := Geometry3D.get_closest_points_between_segments(PLAYER_ANCHOR, player, RIVAL_ANCHOR, rival)
	clash_position = (points[0] + points[1]) * 0.5
	return points[0].distance_to(points[1]) < 0.7 and clash_position.y > 6.0

func finish(outcome: String, reason: String = "string_cut") -> void:
	if state == "finished":
		return
	result_reason = reason
	events.append("round_end")
	if outcome == "win":
		score += 500 + int(player_health * 5.0)
	state = "finished"
	result = outcome
	contact = false
