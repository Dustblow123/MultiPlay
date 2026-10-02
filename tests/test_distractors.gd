extends TestCase
## Distracteurs du QCM (4.8).

var rng := RandomNumberGenerator.new()


func setup() -> void:
	rng.seed = 42


func test_never_the_answer_and_all_distinct() -> void:
	for a in range(1, 11):
		for b in range(a, 11):
			var f := Fact.make(a, b)
			var d := Distractors.generate(f, 3, [], rng)
			assert_eq(d.size(), 3, f.key)
			assert_false(d.has(f.product()), "%s propose la réponse" % f.key)
			assert_eq(d[0] != d[1] and d[1] != d[2] and d[0] != d[2], true, "%s : doublons %s" % [f.key, str(d)])
			for v in d:
				assert_true(v > 0, "%s : distracteur non positif %d" % [f.key, v])


func test_personal_confusions_come_first() -> void:
	var f := Fact.make(7, 8)
	var d := Distractors.generate(f, 3, [54, 48], rng)
	assert_eq(d[0], 54)
	assert_eq(d[1], 48)


func test_neighbors_in_table_then_digit_inversion() -> void:
	var f := Fact.make(7, 8)
	var found_neighbor := false
	var found_inversion := false
	for _i in range(20):
		var d := Distractors.generate(f, 3, [], rng)
		for v in d:
			if v in [49, 63, 48, 64]:
				found_neighbor = true
			if v == 65:
				found_inversion = true
	assert_true(found_neighbor, "voisins 49/63/48/64 attendus")
	assert_true(found_inversion, "inversion 65 attendue au moins une fois")


func test_no_absurd_numbers() -> void:
	for _i in range(200):
		var a := rng.randi_range(2, 10)
		var b := rng.randi_range(2, 10)
		var f := Fact.make(a, b)
		var answer := f.product()
		for v in Distractors.generate(f, 3, [], rng):
			assert_true(Distractors.is_plausible(v, answer), "%s : %d absurde pour %d" % [f.key, v, answer])
			assert_le(v, Distractors.MAX_PLAUSIBLE)
			if answer >= 10:
				assert_ge(v, answer / 3)


func test_plausibility_rules() -> void:
	assert_false(Distractors.is_plausible(56, 56))
	assert_false(Distractors.is_plausible(0, 12))
	assert_false(Distractors.is_plausible(-3, 12))
	assert_false(Distractors.is_plausible(3, 56), "trop petit, réponse évidente")
	assert_false(Distractors.is_plausible(200, 56))
	assert_true(Distractors.is_plausible(54, 56))
