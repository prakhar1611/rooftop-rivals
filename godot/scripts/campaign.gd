extends RefCounted
## Handcrafted, entirely offline progression. Cosmetics never affect simulation.
## record_result updates mode progress only. The caller records aggregate stats.

const CHAPTERS := [
	{"index": 0, "city": "Ahmedabad", "title": "Pol Rooftops", "description": "Learn the line above sunlit old-city courtyards.", "reward": "Rose kite"},
	{"index": 1, "city": "Jaipur", "title": "Pink City Heights", "description": "Trade sweeping attacks across warm sandstone terraces.", "reward": "Three new rival encounters"},
	{"index": 2, "city": "Lucknow", "title": "Courtyard Crosswinds", "description": "Read feints and defend through changing evening winds.", "reward": "Sky Blue kite"},
	{"index": 3, "city": "Varanasi", "title": "River Terrace Finals", "description": "Master the gusts over the river and earn the rooftop crown.", "reward": "Campaign crown"}
]
const STAGES := [
	{"id": "ahmedabad_1", "index": 0, "chapter": 0, "title": "First Crossing", "rival": "Mira", "style": "sweeper", "difficulty": 0, "seed": 101, "weather": "Soft morning breeze", "wind_strength": 0.35, "gust_strength": 0.0, "gust_interval": 12.0, "gust_duration": 1.8, "gust_warning": 2.0, "objective": "Cross strings and find the clean-cut rhythm.", "tip": "Pull during contact. Ease before tension reaches the red zone.", "medal_clean_time": 1.0, "medal_health": 65.0},
	{"id": "ahmedabad_2", "index": 1, "chapter": 0, "title": "Wait, Then Pull", "rival": "Dev", "style": "patient", "difficulty": 0, "seed": 112, "weather": "Steady terrace breeze", "wind_strength": 0.55, "gust_strength": 0.15, "gust_interval": 12.0, "gust_duration": 1.5, "gust_warning": 2.0, "objective": "Draw a patient rival into a clean crossing.", "tip": "Do not hold Pull while chasing. Save tension for the crossing.", "medal_clean_time": 1.5, "medal_health": 65.0},
	{"id": "ahmedabad_3", "index": 2, "chapter": 0, "title": "The Pol Champion", "rival": "Riya", "style": "pressurer", "difficulty": 0, "seed": 123, "weather": "Warm rising breeze", "wind_strength": 0.7, "gust_strength": 0.35, "gust_interval": 10.5, "gust_duration": 1.8, "gust_warning": 2.0, "objective": "Defend a rush and earn your first neighborhood title.", "tip": "Ease to defend a clash, then counter as Riya cools down.", "medal_clean_time": 2.0, "medal_health": 60.0},
	{"id": "jaipur_1", "index": 3, "chapter": 1, "title": "Pink Skyline", "rival": "Kabir", "style": "dancer", "difficulty": 1, "seed": 204, "weather": "Sideways afternoon breeze", "wind_strength": 0.9, "gust_strength": 0.4, "gust_interval": 10.0, "gust_duration": 2.0, "gust_warning": 1.8, "objective": "Catch a moving line instead of chasing the kite.", "tip": "Cut across Kabir's path. Small corrections preserve your angle.", "medal_clean_time": 2.0, "medal_health": 60.0},
	{"id": "jaipur_2", "index": 4, "chapter": 1, "title": "Terrace Sweep", "rival": "Asha", "style": "sweeper", "difficulty": 1, "seed": 215, "weather": "Broad rolling gusts", "wind_strength": 1.05, "gust_strength": 0.6, "gust_interval": 9.5, "gust_duration": 2.2, "gust_warning": 1.8, "objective": "Hold a useful angle through long sweeping attacks.", "tip": "Stay above the rival at contact for a stronger cutting angle.", "medal_clean_time": 2.5, "medal_health": 55.0},
	{"id": "jaipur_3", "index": 5, "chapter": 1, "title": "Sandstone Showdown", "rival": "Arjun", "style": "reader", "difficulty": 1, "seed": 226, "weather": "Quick terrace gusts", "wind_strength": 1.1, "gust_strength": 0.75, "gust_interval": 8.8, "gust_duration": 2.0, "gust_warning": 1.7, "objective": "Break your rhythm against a rival who reads your pulls.", "tip": "Use short pulls and changes of direction rather than one long attack.", "medal_clean_time": 3.0, "medal_health": 55.0},
	{"id": "lucknow_1", "index": 6, "chapter": 2, "title": "Courtyard Patience", "rival": "Noor", "style": "patient", "difficulty": 1, "seed": 307, "weather": "Strong evening drift", "wind_strength": 1.2, "gust_strength": 0.7, "gust_interval": 9.0, "gust_duration": 2.4, "gust_warning": 1.7, "objective": "Make patient attacks while wind shifts the crossing.", "tip": "Approach with cool tension and commit only when the lines meet.", "medal_clean_time": 3.0, "medal_health": 55.0},
	{"id": "lucknow_2", "index": 7, "chapter": 2, "title": "Crosswind Chase", "rival": "Zoya", "style": "dancer", "difficulty": 1, "seed": 318, "weather": "Restless crosswind", "wind_strength": 1.3, "gust_strength": 0.95, "gust_interval": 8.0, "gust_duration": 2.3, "gust_warning": 1.6, "objective": "Intercept a feint without surrendering height.", "tip": "Watch the rival intent and gust warning before committing to a cut.", "medal_clean_time": 3.5, "medal_health": 50.0},
	{"id": "lucknow_3", "index": 8, "chapter": 2, "title": "Evening Rush", "rival": "Ishaan", "style": "pressurer", "difficulty": 2, "seed": 329, "weather": "Heavy dusk gusts", "wind_strength": 1.4, "gust_strength": 1.1, "gust_interval": 7.5, "gust_duration": 2.5, "gust_warning": 1.6, "objective": "Survive an expert rush to win the third neighborhood.", "tip": "A guarded release can save more string than a desperate pull.", "medal_clean_time": 4.0, "medal_health": 45.0},
	{"id": "varanasi_1", "index": 9, "chapter": 3, "title": "River Read", "rival": "Anaya", "style": "reader", "difficulty": 2, "seed": 410, "weather": "River crosscurrents", "wind_strength": 1.45, "gust_strength": 1.1, "gust_interval": 7.8, "gust_duration": 2.5, "gust_warning": 1.6, "objective": "Outthink an expert defender in a shifting river breeze.", "tip": "Change your approach after a blocked cut. Repeating a pull is predictable.", "medal_clean_time": 4.0, "medal_health": 45.0},
	{"id": "varanasi_2", "index": 10, "chapter": 3, "title": "Last Light Duel", "rival": "Vihaan", "style": "champion", "difficulty": 2, "seed": 421, "weather": "Long twilight gusts", "wind_strength": 1.55, "gust_strength": 1.3, "gust_interval": 7.2, "gust_duration": 2.8, "gust_warning": 1.7, "objective": "Adapt as the champion switches between pressure and defense.", "tip": "Recover when the rival guards, then attack from a stronger angle.", "medal_clean_time": 4.5, "medal_health": 40.0},
	{"id": "varanasi_3", "index": 11, "chapter": 3, "title": "The Rooftop Crown", "rival": "Tara", "style": "champion", "difficulty": 2, "seed": 432, "weather": "Festival skyline gusts", "wind_strength": 1.65, "gust_strength": 1.5, "gust_interval": 6.8, "gust_duration": 2.8, "gust_warning": 1.8, "objective": "Bring every skill together and become rooftop champion.", "tip": "Read the gust, preserve your string, and make each clean crossing count.", "medal_clean_time": 5.0, "medal_health": 35.0}
]
const TOURNAMENT_ROUNDS := [
	{"title": "Quarterfinal", "rival": "Kabir", "style": "dancer", "difficulty": 1, "weather": "Rolling afternoon breeze", "wind_strength": 0.9, "gust_strength": 0.55, "gust_interval": 9.5, "gust_duration": 2.0, "gust_warning": 1.8, "tip": "Intercept the dancer's line rather than following the kite."},
	{"title": "Semifinal", "rival": "Anaya", "style": "reader", "difficulty": 1, "weather": "Evening crosswind", "wind_strength": 1.2, "gust_strength": 0.9, "gust_interval": 8.5, "gust_duration": 2.3, "gust_warning": 1.7, "tip": "Change your attack rhythm to get past a patient guard."},
	{"title": "Final", "rival": "Tara", "style": "champion", "difficulty": 2, "weather": "Festival final gusts", "wind_strength": 1.45, "gust_strength": 1.2, "gust_interval": 7.5, "gust_duration": 2.5, "gust_warning": 1.8, "tip": "Use height, controlled pulls, and guarded releases together."}
]
const SKIN_NAMES := ["Jade", "Saffron", "Indigo", "Rose", "Sky Blue", "Champion Gold"]
var profile: RefCounted
var _mode := ""
var _stage_index := -1
var _encounter_id := ""

func _init(player_profile: RefCounted = null) -> void:
	profile = player_profile

func get_stages() -> Array:
	return STAGES.duplicate(true)

func get_chapters() -> Array:
	return CHAPTERS.duplicate(true)

func stage_medals(index: int) -> int:
	if profile == null or index < 0 or index >= STAGES.size():
		return 0
	return int(profile.data.stage_medals[index])

func total_medals() -> int:
	var total := 0
	for index in range(STAGES.size()):
		total += stage_medals(index)
	return total

func completed_chapters() -> int:
	var count := 0
	if profile != null:
		for index in range(CHAPTERS.size()):
			if profile.chapter_complete(index):
				count += 1
	return count

func is_stage_unlocked(index: int) -> bool:
	return profile != null and index >= 0 and index < STAGES.size() and (index == 0 or stage_medals(index - 1) > 0)

func next_stage_index() -> int:
	if profile == null:
		return -1
	for index in range(STAGES.size()):
		if stage_medals(index) == 0:
			return index
	# The final stage remains available as a replay once every stage is won.
	return STAGES.size() - 1

func begin_stage(index: int) -> Dictionary:
	if not is_stage_unlocked(index):
		return {}
	_mode = "campaign"
	_stage_index = index
	_encounter_id = STAGES[index].id
	return STAGES[index].duplicate(true)

func has_active_tournament() -> bool:
	return profile != null and profile.data.tournament.status == "active"

func tournament_status() -> Dictionary:
	if profile == null:
		return {"status": "none", "active": false, "round": 0, "round_title": "Quarterfinal", "results": [], "titles": 0}
	var result: Dictionary = profile.data.tournament.duplicate(true)
	result.active = has_active_tournament()
	result.round_title = TOURNAMENT_ROUNDS[clampi(int(result.round), 0, 2)].title if result.status != "champion" else "Champion"
	result.titles = profile.data.tournament_titles
	return result

func begin_tournament() -> Dictionary:
	if profile == null:
		return {}
	# Calling this again resumes instead of erasing a live bracket.
	if not has_active_tournament():
		profile.data.tournament_runs = mini(100000000, profile.data.tournament_runs + 1)
		var run_id := int(profile.data.tournament_runs)
		profile.data.tournament = {"status": "active", "round": 0, "seed": 733 + run_id * 31 % 99900000, "run_id": run_id, "results": []}
		profile.save()
	return next_tournament_encounter()

func _tournament_encounter() -> Dictionary:
	if not has_active_tournament():
		return {}
	var bracket: Dictionary = profile.data.tournament
	var index := int(bracket.round)
	if index < 0 or index >= TOURNAMENT_ROUNDS.size():
		return {}
	var encounter: Dictionary = TOURNAMENT_ROUNDS[index].duplicate(true)
	encounter.id = "cup_%d_%d" % [int(bracket.run_id), index]
	encounter.index = index
	encounter.chapter = 3
	encounter.seed = int(bracket.seed) + index * 17
	encounter.objective = "Win to advance. A loss or draw ends this cup run."
	encounter.medal_clean_time = 0.0
	encounter.medal_health = 0.0
	return encounter

func next_tournament_encounter() -> Dictionary:
	var encounter := _tournament_encounter()
	if encounter.is_empty():
		return {}
	_mode = "tournament"
	_stage_index = -1
	_encounter_id = encounter.id
	return encounter

func abandon_match() -> void:
	# A bracket remains resumable when the player returns to the menu.
	_mode = ""
	_stage_index = -1
	_encounter_id = ""

func clear_active_encounter() -> void:
	abandon_match()

func record_result(model: Variant) -> Dictionary:
	var summary := {
		"accepted": false, "mode": _mode, "medals": 0, "best_medals": 0,
		"improved": false, "unlocked_stage": -1, "chapter_completed": -1,
		"tournament_advanced": false, "tournament_eliminated": false,
		"tournament_champion": false, "next_encounter": {}, "rewards": [], "saved": false
	}
	if profile == null or model == null or not (model is Object or model is Dictionary) or _mode.is_empty():
		return summary
	if model.get("state") != "finished" or model.get("encounter_id") != _encounter_id:
		return summary
	var outcome = model.get("result")
	if outcome not in ["win", "loss", "draw"]:
		return summary
	var prior_skins: Array[bool] = []
	for index in range(SKIN_NAMES.size()):
		prior_skins.append(profile.skin_unlocked(index))
	if _mode == "campaign":
		if not is_stage_unlocked(_stage_index):
			return summary
		var stage: Dictionary = STAGES[_stage_index]
		var previous := stage_medals(_stage_index)
		var chapter_was_complete: bool = profile.chapter_complete(int(stage.chapter))
		var match_score := int(_safe_number(model.get("score"), 0.0, 100000000.0))
		profile.data.stage_best_scores[_stage_index] = maxi(profile.data.stage_best_scores[_stage_index], match_score)
		if outcome == "win":
			var medals := 1
			if _safe_number(model.get("clean_cut_time"), 0.0, 120.0) >= float(stage.medal_clean_time):
				medals += 1
			if _safe_number(model.get("player_health"), 0.0, 100.0) >= float(stage.medal_health):
				medals += 1
			summary.medals = medals
			profile.data.stage_medals[_stage_index] = maxi(previous, medals)
			summary.improved = medals > previous
			if previous == 0 and _stage_index + 1 < STAGES.size():
				summary.unlocked_stage = _stage_index + 1
			if not chapter_was_complete and profile.chapter_complete(int(stage.chapter)):
				summary.chapter_completed = int(stage.chapter)
			summary.best_medals = stage_medals(_stage_index)
		else:
			summary.best_medals = previous
	else:
		if not has_active_tournament():
			return summary
		var bracket: Dictionary = profile.data.tournament
		var expected := _tournament_encounter()
		if expected.is_empty() or expected.id != _encounter_id:
			return summary
		bracket.results.append(outcome)
		if outcome == "win":
			bracket.round += 1
			if bracket.round == 3:
				bracket.status = "champion"
				profile.data.tournament_titles = mini(100000000, profile.data.tournament_titles + 1)
				summary.tournament_champion = true
			else:
				summary.tournament_advanced = true
				summary.next_encounter = _tournament_encounter()
		else:
			bracket.status = "eliminated"
			summary.tournament_eliminated = true
	for index in range(SKIN_NAMES.size()):
		if not prior_skins[index] and profile.skin_unlocked(index):
			summary.rewards.append(SKIN_NAMES[index] + " kite unlocked")
	summary.accepted = true
	# Consume before saving, so repeated finish callbacks cannot award twice.
	abandon_match()
	summary.saved = profile.save()
	return summary

func _safe_number(value: Variant, low: float, high: float) -> float:
	if not (value is float or value is int) or not is_finite(float(value)):
		return low
	return clampf(float(value), low, high)
