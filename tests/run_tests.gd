extends SceneTree
## Lance tous les tests unitaires et la simulation d'élèves fictifs.
##
##   godot --headless --path . -s tests/run_tests.gd
##   godot --headless --path . -s tests/run_tests.gd -- --quick   (sans la simulation longue)
##   godot --headless --path . -s tests/run_tests.gd -- --verbose (nom de chaque test)
##
## Code de sortie : 0 si tout passe, 1 sinon.

const SUITES := [
	"res://tests/test_fact.gd",
	"res://tests/test_distractors.gd",
	"res://tests/test_engine.gd",
	"res://tests/test_persistence.gd",
	"res://tests/simulation/test_simulation.gd",
]


func _init() -> void:
	var quick := "--quick" in OS.get_cmdline_user_args()
	TestCase.verbose = "--verbose" in OS.get_cmdline_user_args()
	var total_passed := 0
	var total_failed := 0
	var all_failures: Array = []
	for path in SUITES:
		if quick and path.contains("simulation"):
			continue
		var script: GDScript = load(path)
		var suite: TestCase = script.new()
		var start := Time.get_ticks_msec()
		var result: Dictionary = suite.run()
		var elapsed := Time.get_ticks_msec() - start
		total_passed += result["passed"]
		total_failed += result["failed"]
		all_failures.append_array(result["failures"])
		print("%-45s %3d ok, %3d échec(s)  (%d ms)" % [path.get_file(), result["passed"], result["failed"], elapsed])
	print("")
	for f in all_failures:
		print("ÉCHEC  " + f)
	print("Total : %d réussi(s), %d échec(s)" % [total_passed, total_failed])
	quit(0 if total_failed == 0 else 1)
