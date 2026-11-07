extends SceneTree
const Profile = preload("res://scripts/player_profile.gd")
const Campaign = preload("res://scripts/campaign.gd")
const PATH := "user://test_campaign_isolated.json"
var failures := 0
var checks := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func result_for(encounter: Dictionary, outcome: String = "win", clean: float = 100.0, health: float = 100.0, points: int = 1500) -> Dictionary:
	return {"state": "finished", "encounter_id": encounter.get("id", ""), "result": outcome, "clean_cut_time": clean, "player_health": health, "score": points}

func write_raw(value: String) -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(value)
	file.close()

func fresh():
	var profile = Profile.new()
	profile.load_profile(PATH)
	profile.reset_progress()
	return profile

func _initialize() -> void:
	_test_campaign()
	_test_tournament()
	_test_migration_and_validation()
	DirAccess.remove_absolute(PATH)
	print("%s: %d campaign/profile checks (%d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)

func _test_campaign() -> void:
	var profile = fresh()
	var campaign = Campaign.new(profile)
	check(campaign.get_stages().size() == 12 and campaign.get_chapters().size() == 4, "Twelve stages across four neighborhoods")
	check(campaign.next_stage_index() == 0 and campaign.completed_chapters() == 0 and campaign.total_medals() == 0, "Empty campaign starts at first crossing")
	check(not campaign.is_stage_unlocked(-1) and not campaign.is_stage_unlocked(12), "Stage indices are bounded")
	check(campaign.begin_stage(-1).is_empty() and campaign.begin_stage(12).is_empty(), "Invalid begin is harmless")
	for index in range(12):
		check(campaign.is_stage_unlocked(index) == (index == 0), "Initial unlock gate %d" % index)
	check(campaign.begin_stage(1).is_empty(), "Locked stage cannot start")
	var stages: Array = campaign.get_stages()
	stages[0].rival = "Modified"
	check(campaign.get_stages()[0].rival == "Mira", "Callers cannot mutate handcrafted encounters")
	var encounter: Dictionary = campaign.begin_stage(0)
	var pending := result_for(encounter)
	pending.state = "playing"
	check(not campaign.record_result(pending).accepted, "Unfinished match cannot award medals")
	pending.state = "finished"
	pending.encounter_id = "wrong"
	check(not campaign.record_result(pending).accepted, "Wrong encounter cannot award medals")
	pending = result_for(encounter, "mystery")
	check(not campaign.record_result(pending).accepted, "Unknown result cannot award medals")
	check(not campaign.record_result(null).accepted and not campaign.record_result(42).accepted, "Malformed result input is harmless")
	var report: Dictionary = campaign.record_result(result_for(encounter, "loss"))
	check(report.accepted and report.medals == 0 and not campaign.is_stage_unlocked(1), "Loss does not unlock the next stage")
	encounter = campaign.begin_stage(0)
	report = campaign.record_result(result_for(encounter, "draw"))
	check(report.medals == 0 and not campaign.is_stage_unlocked(1), "Draw does not unlock the next stage")
	encounter = campaign.begin_stage(0)
	report = campaign.record_result(result_for(encounter, "win", 0.0, 1.0, 500))
	check(report.medals == 1 and report.best_medals == 1 and report.improved and report.unlocked_stage == 1, "Win earns one medal and next stage")
	check(profile.data.matches == 0 and profile.data.wins == 0, "Campaign does not double count aggregate match stats")
	check(not campaign.record_result(result_for(encounter)).accepted and campaign.stage_medals(0) == 1, "A finish callback is consumed once")
	encounter = campaign.begin_stage(0)
	report = campaign.record_result(result_for(encounter, "win", 1.0, 1.0, 700))
	check(report.medals == 2 and report.best_medals == 2 and report.unlocked_stage == -1, "Clean-cut skill independently adds one medal")
	encounter = campaign.begin_stage(0)
	report = campaign.record_result(result_for(encounter, "win", 0.0, 65.0, 600))
	check(report.medals == 2 and not report.improved, "Healthy finish independently adds one medal")
	encounter = campaign.begin_stage(0)
	report = campaign.record_result(result_for(encounter, "win", 1.0, 65.0, 2000))
	check(report.medals == 3 and report.best_medals == 3 and report.improved, "Both skills earn three medals at threshold")
	encounter = campaign.begin_stage(0)
	report = campaign.record_result(result_for(encounter, "win", 0.0, 1.0, -10))
	check(report.medals == 1 and report.best_medals == 3 and not report.improved and profile.data.stage_best_scores[0] == 2000, "Replays preserve best medals and score")
	for index in range(1, 12):
		check(campaign.is_stage_unlocked(index), "Previous win unlocks stage %d" % index)
		if index < 11:
			check(not campaign.is_stage_unlocked(index + 1), "Future gate remains shut before stage %d win" % index)
		encounter = campaign.begin_stage(index)
		check(encounter.id == campaign.get_stages()[index].id and encounter.chapter == index / 3, "Encounter identity and chapter %d" % index)
		report = campaign.record_result(result_for(encounter))
		check(report.accepted and report.medals == 3, "Stage %d result recorded" % index)
		if index % 3 == 2:
			check(report.chapter_completed == index / 3, "Chapter completion emitted at gate %d" % index)
		else:
			check(report.chapter_completed == -1, "Partial chapter never emits completion")
		if index == 2:
			check(profile.skin_unlocked(3) and report.rewards == ["Rose kite unlocked"], "First chapter awards Rose once")
		if index == 8:
			check(profile.skin_unlocked(4) and report.rewards == ["Sky Blue kite unlocked"], "Third chapter awards Sky Blue once")
	check(campaign.total_medals() == 36 and campaign.completed_chapters() == 4 and campaign.next_stage_index() == 11, "Full campaign tracks all medals and replay target")
	for index in [2, 8, 11]:
		encounter = campaign.begin_stage(index)
		report = campaign.record_result(result_for(encounter))
		check(report.chapter_completed == -1 and report.rewards.is_empty(), "Chapter and cosmetics never re-award on replay %d" % index)
	check(not profile.skin_unlocked(-1) and not profile.skin_unlocked(6) and not profile.skin_unlocked(5), "Cosmetics are bounded and champion is cup-only")
	encounter = campaign.begin_stage(3)
	campaign.clear_active_encounter()
	check(not campaign.record_result(result_for(encounter)).accepted, "Abandoned stage cannot award from unrelated finish")
	var copy = Profile.new()
	copy.load_profile(PATH)
	var resumed = Campaign.new(copy)
	check(resumed.total_medals() == 36 and resumed.completed_chapters() == 4, "Campaign milestones survive restart")
	encounter = resumed.begin_stage(0)
	pending = result_for(encounter)
	pending.clean_cut_time = NAN
	pending.player_health = INF
	pending.score = INF
	report = resumed.record_result(pending)
	check(report.medals == 1 and copy.data.stage_best_scores[0] == 2000, "Non-finite measurements cannot manufacture skill medals or best score")
	copy.save_path = "user://missing-campaign-directory/profile.json"
	encounter = resumed.begin_stage(0)
	report = resumed.record_result(result_for(encounter))
	check(report.accepted and not report.saved and copy.last_error != "", "Progress write failure remains visible")
	var no_profile = Campaign.new()
	check(no_profile.begin_stage(0).is_empty() and no_profile.begin_tournament().is_empty() and no_profile.next_stage_index() == -1, "Unassigned controller handles empty state safely")

func _test_tournament() -> void:
	var profile = fresh()
	var campaign = Campaign.new(profile)
	check(not campaign.has_active_tournament() and campaign.next_tournament_encounter().is_empty(), "No cup round exists before starting")
	var encounter: Dictionary = campaign.begin_tournament()
	check(encounter.title == "Quarterfinal" and campaign.tournament_status().round == 0, "Cup begins at quarterfinal")
	var run_id: int = profile.data.tournament.run_id
	check(campaign.begin_tournament().id == encounter.id and profile.data.tournament.run_id == run_id, "Repeated begin resumes rather than replacing a bracket")
	campaign.clear_active_encounter()
	check(campaign.has_active_tournament() and not campaign.record_result(result_for(encounter)).accepted, "Leaving a cup match preserves bracket but rejects abandoned result")
	encounter = campaign.next_tournament_encounter()
	var report: Dictionary = campaign.record_result(result_for(encounter))
	check(report.tournament_advanced and not report.tournament_champion and report.next_encounter.title == "Semifinal", "Quarterfinal victory advances exactly one round")
	check(profile.data.tournament.round == 1 and profile.data.tournament.results == ["win"], "Saved bracket records quarterfinal win")
	check(not campaign.record_result(result_for(encounter)).accepted and profile.data.tournament.round == 1, "Repeated tournament result cannot advance twice")
	var reloaded = Profile.new()
	reloaded.load_profile(PATH)
	campaign = Campaign.new(reloaded)
	encounter = campaign.begin_tournament()
	check(encounter.title == "Semifinal" and reloaded.data.tournament.run_id == run_id and reloaded.data.tournament_runs == 1, "Restart resumes semifinal in the same run")
	report = campaign.record_result(result_for(encounter))
	check(report.tournament_advanced and report.next_encounter.title == "Final", "Semifinal victory unlocks final")
	var reloaded_final = Profile.new()
	reloaded_final.load_profile(PATH)
	campaign = Campaign.new(reloaded_final)
	encounter = campaign.next_tournament_encounter()
	check(encounter.title == "Final" and campaign.tournament_status().round_title == "Final", "Final survives a second restart")
	report = campaign.record_result(result_for(encounter))
	check(report.tournament_champion and not report.tournament_advanced and not campaign.has_active_tournament(), "Final completes the bracket")
	check(reloaded_final.data.tournament_titles == 1 and reloaded_final.skin_unlocked(5) and report.rewards == ["Champion Gold kite unlocked"], "Final awards one title and cosmetic")
	check(campaign.next_tournament_encounter().is_empty() and not campaign.record_result(result_for(encounter)).accepted, "Completed cup cannot submit another final")
	check(reloaded_final.data.tournament_titles == 1 and campaign.tournament_status().status == "champion", "Final title remains single")
	var old_final := result_for(encounter)
	encounter = campaign.begin_tournament()
	check(reloaded_final.data.tournament_runs == 2 and encounter.title == "Quarterfinal", "Another cup starts a fresh unique bracket")
	check(not campaign.record_result(old_final).accepted, "Stale final cannot advance a fresh cup")
	report = campaign.record_result(result_for(encounter, "loss"))
	check(report.tournament_eliminated and not report.tournament_advanced and reloaded_final.data.tournament.round == 0, "Quarterfinal defeat eliminates without advance")
	check(reloaded_final.data.tournament.results == ["loss"] and campaign.next_tournament_encounter().is_empty(), "Eliminated bracket has no next encounter")
	var failed_copy = Profile.new()
	failed_copy.load_profile(PATH)
	check(failed_copy.data.tournament.status == "eliminated" and failed_copy.data.tournament.round == 0, "Elimination survives restart")
	for fail_round in range(3):
		encounter = campaign.begin_tournament()
		for previous in range(fail_round):
			campaign.record_result(result_for(encounter))
			encounter = campaign.next_tournament_encounter()
		report = campaign.record_result(result_for(encounter, "draw"))
		check(report.tournament_eliminated and not report.tournament_champion and reloaded_final.data.tournament.round == fail_round, "Draw never advances round %d" % fail_round)
		check(reloaded_final.data.tournament_titles == 1, "Draw never awards a title in round %d" % fail_round)
	encounter = campaign.begin_tournament()
	for round_index in range(3):
		report = campaign.record_result(result_for(encounter))
		if round_index < 2:
			encounter = campaign.next_tournament_encounter()
	check(reloaded_final.data.tournament_titles == 2 and report.rewards.is_empty(), "A second full cup earns a title but not another cosmetic reward")
	check(reloaded_final.data.matches == 0, "Cup progression leaves aggregate statistics to the caller")

func _test_migration_and_validation() -> void:
	write_raw('{"wins":5,"losses":2,"draws":1,"matches":8,"best_score":2400,"difficulty":2,"skin":2,"sound":false,"haptics":true,"left_handed":true,"reduced_motion":true,"tutorial_seen":true}')
	var profile = Profile.new()
	profile.load_profile(PATH)
	check(profile.data.schema_version == 2 and profile.data.wins == 5 and profile.data.matches == 8 and profile.data.skin == 2, "0.9.1 save migrates aggregates and unlocked kite")
	check(not profile.data.sound and profile.data.haptics and profile.data.left_handed and profile.data.reduced_motion and profile.data.tutorial_seen, "0.9.1 migration keeps accessibility and preferences")
	check(profile.data.stage_medals.size() == 12 and profile.data.stage_medals.count(0) == 12 and profile.data.tournament.status == "none", "0.9.1 gets safe empty campaign and bracket")
	check(profile.save(), "Migrated profile saves successfully")
	var copy = Profile.new()
	copy.load_profile(PATH)
	check(copy.data.best_score == 2400 and copy.data.stage_medals == profile.data.stage_medals, "Migrated profile round-trips")
	write_raw('{"wins":-99,"matches":1e100,"difficulty":"2","skin":5,"stage_medals":[3,0,3,3,3,3,3,3,3,3,3,3,99],"stage_best_scores":[-1,"bad",1e100],"tournament_titles":-4,"tournament_runs":"bad","tournament":{"status":"active","round":2,"run_id":1,"seed":1,"results":[]},"email":"not-saved@example.invalid"}')
	copy.load_profile(PATH)
	check(copy.data.wins == 0 and copy.data.matches == 100000000 and copy.data.difficulty == 1 and copy.data.skin == 0, "Bogus scalar values are bounded and wrong types ignored")
	check(copy.data.stage_medals == [3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], "Out-of-order medals cannot bypass sequential gates")
	check(copy.data.stage_best_scores[0] == 0 and copy.data.stage_best_scores[1] == 0 and copy.data.stage_best_scores[2] == 100000000, "Bogus per-stage scores safely bounded")
	check(copy.data.tournament.status == "none" and copy.data.tournament_titles == 0 and not copy.data.has("email"), "Unbacked round and unrecognized personal keys rejected")
	for bracket in [
		{"status": "active", "round": -1, "run_id": 1, "results": []},
		{"status": "active", "round": 0.5, "run_id": 1, "results": []},
		{"status": "active", "round": 2, "run_id": 1, "results": ["win", "loss"]},
		{"status": "active", "round": 3, "run_id": 1, "results": ["win", "win", "win"]},
		{"status": "champion", "round": 3, "run_id": 1, "results": ["win", "win", "draw"]},
		{"status": "champion", "round": 2, "run_id": 1, "results": ["win", "win"]},
		{"status": "eliminated", "round": 1, "run_id": 1, "results": ["loss", "draw"]},
		{"status": "eliminated", "round": 1, "run_id": 1, "results": ["win", "win"]},
		{"status": "active", "round": 0, "run_id": 0, "results": []},
		{"status": "active", "round": "0", "run_id": 1, "results": []}
	]:
		write_raw(JSON.stringify({"tournament": bracket}))
		copy.load_profile(PATH)
		check(copy.data.tournament.status == "none", "Invalid bracket state rejected: %s" % JSON.stringify(bracket))
	for round_index in range(3):
		var wins: Array = []
		for prior in range(round_index):
			wins.append("win")
		write_raw(JSON.stringify({"tournament": {"status": "active", "round": round_index, "seed": 777, "run_id": 6, "results": wins}}))
		copy.load_profile(PATH)
		check(copy.data.tournament.status == "active" and copy.data.tournament.round == round_index and copy.data.tournament_runs == 6, "Valid active round %d restored" % round_index)
	write_raw("{broken")
	copy.load_profile(PATH)
	check(not copy.save_allowed and not copy.save() and FileAccess.get_file_as_string(PATH) == "{broken", "Corruption never silently destroys source save")
	write_raw("[]")
	copy.load_profile(PATH)
	check(not copy.save_allowed and copy.data.matches == 0, "Wrong root type uses protected safe defaults")
	write_raw('{"schema_version":999,"wins":20}')
	copy.load_profile(PATH)
	check(not copy.save_allowed and not copy.save() and FileAccess.get_file_as_string(PATH).contains("999"), "Future schemas cannot be silently downgraded")
	check(copy.reset_progress() and copy.save_allowed and copy.data.tournament.status == "none" and copy.data.tournament_titles == 0, "Explicit reset clears and unblocks all progression")
	copy.record_match("typo", 999)
	check(copy.data.matches == 0, "Unknown aggregate result is ignored")
	copy.record_match("win", -500)
	check(copy.data.best_score == 0 and copy.data.wins == 1, "Negative aggregate score cannot reduce best")
