extends SceneTree
const Profile = preload("res://scripts/player_profile.gd")
var failures := 0
var checks := 0
const PATH := "user://test_profile_isolated.json"

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	var profile = Profile.new()
	profile.load_profile(PATH)
	profile.reset_progress()
	check(profile.data.wins == 0 and profile.data.sound, "Initial defaults")
	check(not profile.data.haptics and not profile.data.left_handed, "Safe optional defaults")
	check(profile.skin_unlocked(0) and not profile.skin_unlocked(1), "Only starter kite unlocked")
	profile.record_match("win", 1234)
	check(profile.data.wins == 1 and profile.data.matches == 1 and profile.data.best_score == 1234, "Aggregate score stored")
	check(profile.skin_unlocked(1) and not profile.skin_unlocked(2), "One-win kite unlock")
	profile.data.left_handed = true
	profile.data.skin = 1
	profile.save()
	var copy = Profile.new()
	copy.load_profile(PATH)
	check(copy.data.left_handed and copy.data.skin == 1 and copy.data.best_score == 1234, "Settings and progress survive reload")
	copy.record_match("loss", 20)
	check(copy.data.best_score == 1234 and copy.data.losses == 1, "Lower score does not replace best")
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string("{bad json")
	file.close()
	copy.load_profile(PATH)
	check(copy.data.wins == 0 and copy.last_error != "", "Corrupt save fails safely")
	check(not copy.save(), "Unreadable progress is not silently overwritten")
	check(FileAccess.get_file_as_string(PATH) == "{bad json", "Corrupt source remains available for recovery")
	file = FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string('{"wins":-12,"difficulty":99,"skin":2,"sound":"bad","left_handed":true,"email":"never-store@example.invalid"}')
	file.close()
	copy.load_profile(PATH)
	check(copy.data.wins == 0 and copy.data.difficulty == 2 and copy.data.skin == 0, "Malformed values clamped and locked cosmetic rejected")
	check(copy.data.sound and copy.data.left_handed and not copy.data.has("email"), "Wrong types and unknown personal-data keys ignored")
	copy.reset_progress()
	check(copy.data.matches == 0 and copy.data.skin == 0, "Erase restores defaults")
	copy.save_path = "user://missing-test-directory/profile.json"
	check(not copy.save() and copy.last_error != "", "Write failure is reported")
	DirAccess.remove_absolute(PATH)
	print("%s: %d profile checks (%d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
