extends TestCase
## Sauvegarde JSON locale (9) et rejeu du journal (4.9).


func _play_random_sessions(engine: LearningEngine, sessions: int, items: int, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for s in range(sessions):
		engine.start_session(s * 2)
		for _i in range(items):
			var item := engine.next_item()
			var correct := rng.randf() < 0.8
			var given: int = item["accepted"][0] if correct else item["answer"] + 3
			engine.report_result(item, given, rng.randi_range(500, 5000))
		engine.end_session()


func test_engine_roundtrip_to_dict() -> void:
	var engine := LearningEngine.new(null, 7)
	_play_random_sessions(engine, 4, 20, 1)
	var d := engine.to_dict()
	var json := JSON.stringify(d)
	var back: Dictionary = JSON.parse_string(json)
	var restored := LearningEngine.from_dict(back, null, 7)
	assert_eq(restored.session_id, engine.session_id)
	assert_eq(restored.journal.size(), engine.journal.size())
	for key in engine.states:
		assert_eq(restored.states[key].to_dict(), engine.states[key].to_dict(), key)
	assert_eq(restored.calibration, engine.calibration)


func test_rebuild_from_journal_matches_live_state() -> void:
	var engine := LearningEngine.new(null, 11)
	_play_random_sessions(engine, 6, 25, 2)
	var json := JSON.stringify(engine.journal)
	var entries: Array = JSON.parse_string(json)
	var rebuilt := LearningEngine.rebuild_from_journal(entries)
	assert_eq(rebuilt.session_id, engine.session_id)
	assert_eq(rebuilt.current_day, engine.current_day)
	for key in engine.states:
		assert_eq(rebuilt.states[key].to_dict(), engine.states[key].to_dict(), key)
	assert_eq(rebuilt.calibration, engine.calibration)


func test_profile_store_save_and_load() -> void:
	var profile := Profile.create("Test Enfant")
	profile.id = "test_profile_store"
	profile.stardust = 42
	profile.settings["deadzone"] = 0.5
	_play_random_sessions(profile.engine, 2, 10, 3)
	assert_true(ProfileStore.save(profile))
	var ids := []
	for p in ProfileStore.list_profiles():
		ids.append(p["id"])
	assert_true(ids.has("test_profile_store"))
	var loaded := ProfileStore.load_profile("test_profile_store")
	assert_true(loaded != null)
	assert_eq(loaded.name, "Test Enfant")
	assert_eq(loaded.stardust, 42)
	assert_eq(loaded.settings["deadzone"], 0.5)
	assert_eq(loaded.engine.session_id, 2)
	assert_eq(loaded.engine.journal.size(), profile.engine.journal.size())
	for key in profile.engine.states:
		assert_eq(loaded.engine.states[key].to_dict(), profile.engine.states[key].to_dict(), key)
	ProfileStore.delete("test_profile_store")
	assert_true(ProfileStore.load_profile("test_profile_store") == null)
