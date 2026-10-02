class_name TestCase
extends RefCounted
## Mini-cadre de test sans dépendance externe. Chaque méthode `test_*` est
## exécutée par `tests/run_tests.gd` (Godot en mode headless).

static var verbose: bool = false

var _failures: Array = []
var _current: String = ""


func setup() -> void:
	pass


func run() -> Dictionary:
	var passed := 0
	var failed := 0
	for m in get_method_list():
		var name: String = m["name"]
		if not name.begins_with("test_"):
			continue
		_current = name
		if verbose:
			_log_progress(name)
		var before := _failures.size()
		setup()
		call(name)
		if _failures.size() == before:
			passed += 1
		else:
			failed += 1
	return {"passed": passed, "failed": failed, "failures": _failures}


## Trace non tamponnée (utile pour repérer un test qui ne termine pas).
func _log_progress(name: String) -> void:
	var f := FileAccess.open("user://tests_progress.log", FileAccess.READ_WRITE if FileAccess.file_exists("user://tests_progress.log") else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line("%s.%s" % [get_script().resource_path.get_file(), name])
	f.flush()
	f.close()


func fail(message: String) -> void:
	_failures.append("%s.%s : %s" % [get_script().resource_path.get_file(), _current, message])


func assert_true(cond: bool, message: String = "") -> void:
	if not cond:
		fail("attendu vrai. " + message)


func assert_false(cond: bool, message: String = "") -> void:
	if cond:
		fail("attendu faux. " + message)


func assert_eq(actual, expected, message: String = "") -> void:
	if actual != expected:
		fail("attendu %s, obtenu %s. %s" % [str(expected), str(actual), message])


func assert_ne(actual, not_expected, message: String = "") -> void:
	if actual == not_expected:
		fail("valeur inattendue %s. %s" % [str(actual), message])


func assert_ge(actual, minimum, message: String = "") -> void:
	if actual < minimum:
		fail("attendu >= %s, obtenu %s. %s" % [str(minimum), str(actual), message])


func assert_le(actual, maximum, message: String = "") -> void:
	if actual > maximum:
		fail("attendu <= %s, obtenu %s. %s" % [str(maximum), str(actual), message])
