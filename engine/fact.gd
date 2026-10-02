class_name Fact
extends RefCounted
## Un fait de multiplication sous forme canonique (4.1) : petit facteur d'abord.
## 3×7 et 7×3 sont le même fait, de clé "3x7".

var a: int
var b: int

static func make(x: int, y: int) -> Fact:
	var f := Fact.new()
	f.a = mini(x, y)
	f.b = maxi(x, y)
	return f


static func key_of(x: int, y: int) -> String:
	return "%dx%d" % [mini(x, y), maxi(x, y)]


static func from_key(key: String) -> Fact:
	var parts := key.split("x")
	return make(int(parts[0]), int(parts[1]))


## Clé d'orientation : "7x3" signifie « 7 × 3 est affiché ».
static func orientation_key(first: int, second: int) -> String:
	return "%dx%d" % [first, second]


var key: String:
	get:
		return key_of(a, b)


func product() -> int:
	return a * b


## Les faits triviaux (×0, ×1, ×10) servent à l'échauffement et à la calibration.
func is_trivial() -> bool:
	return a in [0, 1, 10] or b in [0, 1, 10]


## Tables auxquelles le fait appartient (3×7 est une planète des systèmes 3 et 7).
func tables() -> Array:
	return [a] if a == b else [a, b]


func belongs_to(table: int) -> bool:
	return a == table or b == table


## Orientations possibles, sous forme [premier, second].
func orientations() -> Array:
	if a == b:
		return [[a, b]]
	return [[a, b], [b, a]]


func _to_string() -> String:
	return key
