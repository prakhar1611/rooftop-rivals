extends RefCounted
## Local-only preferences and progress. No identifiers, accounts or auth tokens.
## The v1 filename is intentionally retained so 0.9.1 saves migrate in place.

const SAVE_PATH := "user://player_profile_v1.json"
const SCHEMA_VERSION := 2
const STAGE_COUNT := 12
const SKIN_COUNT := 6
const MAX_COUNTER := 100000000
const EMPTY_TOURNAMENT := {"status": "none", "round": 0, "seed": 0, "run_id": 0, "results": []}
const DEFAULTS := {
	"schema_version": SCHEMA_VERSION,
	"sound": true, "haptics": false, "reduced_motion": false, "left_handed": false,
	"difficulty": 1, "skin": 0, "wins": 0, "losses": 0, "draws": 0,
	"best_score": 0, "matches": 0, "tutorial_seen": false,
	"stage_medals": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
	"stage_best_scores": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
	"tournament_titles": 0, "tournament_runs": 0,
	"tournament": EMPTY_TOURNAMENT
}
var data := DEFAULTS.duplicate(true)
var save_path := SAVE_PATH
var last_error := ""
var save_allowed := true

func load_profile(path: String = SAVE_PATH) -> void:
	save_path = path
	data = DEFAULTS.duplicate(true)
	last_error = ""
	save_allowed = true
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_error = "Local progress could not be opened."
		save_allowed = false
		return
	# Avoid reading unexpectedly large or unrelated files as game progress.
	if file.get_length() > 1048576:
		file.close()
		last_error = "Local progress was unreadable. Using safe defaults."
		save_allowed = false
		return
	var source := file.get_as_text()
	var read_error := file.get_error()
	file.close()
	var parser := JSON.new()
	var error := parser.parse(source)
	var parsed = parser.data
	if read_error != OK or error != OK or not parsed is Dictionary:
		last_error = "Local progress was unreadable. Using safe defaults."
		save_allowed = false
		return
	# A future schema must not be silently downgraded by an older app.
	if _integer(parsed.get("schema_version"), 0, MAX_COUNTER) > SCHEMA_VERSION:
		last_error = "This progress was saved by a newer game version. Update the game or reset progress."
		save_allowed = false
		return
	for key in ["sound", "haptics", "reduced_motion", "left_handed", "tutorial_seen"]:
		if parsed.get(key) is bool:
			data[key] = parsed[key]
	for key in ["wins", "losses", "draws", "best_score", "matches", "tournament_titles", "tournament_runs"]:
		data[key] = _integer(parsed.get(key), 0, MAX_COUNTER)
	data.difficulty = _integer(parsed.get("difficulty"), 0, 2, 1)
	data.skin = _integer(parsed.get("skin"), 0, SKIN_COUNT - 1)
	var medals = parsed.get("stage_medals")
	var scores = parsed.get("stage_best_scores")
	var previous_won := true
	for index in range(STAGE_COUNT):
		if medals is Array and index < medals.size() and previous_won:
			data.stage_medals[index] = _integer(medals[index], 0, 3)
		# Progress beyond a locked gate cannot create an unlock on load.
		previous_won = previous_won and data.stage_medals[index] > 0
		if scores is Array and index < scores.size():
			data.stage_best_scores[index] = _integer(scores[index], 0, MAX_COUNTER)
	data.tournament = _validated_tournament(parsed.get("tournament"))
	data.tournament_runs = maxi(data.tournament_runs, data.tournament.run_id)
	if not skin_unlocked(data.skin):
		data.skin = 0

func _integer(value: Variant, low: int, high: int, fallback: int = 0) -> int:
	if not (value is int or value is float) or not is_finite(float(value)):
		return fallback
	# Clamp before casting, including enormous JSON numbers.
	return int(clampf(float(value), float(low), float(high)))

func _validated_tournament(value: Variant) -> Dictionary:
	var empty := EMPTY_TOURNAMENT.duplicate(true)
	if not value is Dictionary:
		return empty
	var status = value.get("status")
	var results = value.get("results")
	if not status is String or status not in ["active", "eliminated", "champion"] or not results is Array:
		return empty
	if results.size() > 3:
		return empty
	var round_value = value.get("round")
	if not (round_value is int or round_value is float) or not is_finite(float(round_value)):
		return empty
	if float(round_value) != floorf(float(round_value)) or float(round_value) < 0 or float(round_value) > 3:
		return empty
	var round_index := int(round_value)
	var run_id := _integer(value.get("run_id"), 0, MAX_COUNTER)
	if run_id < 1:
		return empty
	# Each saved round must be backed by exactly its preceding victories.
	if status == "active":
		if round_index > 2 or results.size() != round_index:
			return empty
	elif status == "champion":
		if round_index != 3 or results.size() != 3:
			return empty
	else:
		if round_index > 2 or results.size() != round_index + 1 or results[-1] not in ["loss", "draw"]:
			return empty
	for index in range(results.size()):
		if status == "eliminated" and index == results.size() - 1:
			continue
		if results[index] != "win":
			return empty
	return {"status": status, "round": round_index, "seed": _integer(value.get("seed"), 0, MAX_COUNTER), "run_id": run_id, "results": results.duplicate()}

func save() -> bool:
	if not save_allowed:
		last_error = "Existing progress is unreadable or newer. Reset it in Privacy to save again."
		return false
	var temp := save_path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		last_error = "Progress could not be saved on this device."
		return false
	file.store_string(JSON.stringify(data))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		last_error = "Progress could not be fully written. Previous progress is unchanged."
		DirAccess.remove_absolute(temp)
		return false
	var error := DirAccess.rename_absolute(temp, save_path)
	if error != OK:
		last_error = "Progress could not be saved on this device."
		DirAccess.remove_absolute(temp)
		return false
	last_error = ""
	return true

func record_match(outcome: String, score: int) -> void:
	if outcome not in ["win", "loss", "draw"]:
		return
	data.matches = mini(MAX_COUNTER, data.matches + 1)
	var key := {"win": "wins", "loss": "losses", "draw": "draws"}[outcome] as String
	data[key] = mini(MAX_COUNTER, data[key] + 1)
	data.best_score = maxi(data.best_score, clampi(score, 0, MAX_COUNTER))
	save()

func chapter_complete(index: int) -> bool:
	if index < 0 or index >= 4:
		return false
	for stage in range(index * 3, index * 3 + 3):
		if data.stage_medals[stage] < 1:
			return false
	return true

func skin_unlocked(index: int) -> bool:
	match index:
		0: return true
		1: return data.wins >= 1
		2: return data.wins >= 5
		3: return chapter_complete(0)
		4: return chapter_complete(2)
		5: return data.tournament_titles >= 1
	return false

func reset_progress() -> bool:
	data = DEFAULTS.duplicate(true)
	save_allowed = true
	return save()
