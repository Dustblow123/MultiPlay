extends TestCase
## Forme canonique et propriétés d'un fait (4.1).


func test_canonical_key_small_factor_first() -> void:
	assert_eq(Fact.key_of(7, 3), "3x7")
	assert_eq(Fact.key_of(3, 7), "3x7")
	assert_eq(Fact.make(9, 4).key, "4x9")
	assert_eq(Fact.from_key("4x9").product(), 36)


func test_trivial_facts() -> void:
	assert_true(Fact.make(1, 7).is_trivial())
	assert_true(Fact.make(10, 6).is_trivial())
	assert_true(Fact.make(0, 3).is_trivial())
	assert_false(Fact.make(6, 7).is_trivial())


func test_orientations_and_tables() -> void:
	assert_eq(Fact.make(3, 7).orientations(), [[3, 7], [7, 3]])
	assert_eq(Fact.make(5, 5).orientations(), [[5, 5]])
	assert_eq(Fact.make(3, 7).tables(), [3, 7])
	assert_true(Fact.make(3, 7).belongs_to(7))
	assert_false(Fact.make(3, 7).belongs_to(4))


func test_engine_builds_55_facts_for_tables_1_to_10() -> void:
	var engine := LearningEngine.new(null, 1)
	assert_eq(engine.states.size(), 55)
	var cfg := EngineConfig.new()
	cfg.include_zero = true
	assert_eq(LearningEngine.new(cfg, 1).states.size(), 66)
