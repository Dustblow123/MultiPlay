extends Node
## Autoload « Sfx » : effets rétro générés en code au démarrage (ondes carrées
## et triangulaires avec enveloppe), sans asset ni licence à gérer. Les sons
## suivent la grille de retours du document (8) : effet net et positif sur une
## bonne réponse, son doux et non punitif sur une erreur, musique qui
## s'intensifie sur une série, jingle de colonisation.

const SAMPLE_RATE := 22050
const POOL_SIZE := 6

var _streams: Dictionary = {}
var _players: Array = []
var _next_player: int = 0
var enabled: bool = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for _i in range(POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	_streams["good"] = _build([[660, 0.06, 0], [880, 0.08, 0]], 0.5)
	_streams["fast"] = _build([[660, 0.05, 0], [880, 0.05, 0], [1320, 0.1, 0]], 0.5)
	_streams["error"] = _build([[220, 0.18, 1]], 0.25)
	_streams["shoot"] = _build([[1200, 0.03, 0], [700, 0.04, 0]], 0.3)
	_streams["scan"] = _build([[440, 0.08, 1], [550, 0.08, 1], [660, 0.12, 1]], 0.35)
	_streams["combo"] = _build([[523, 0.06, 0], [659, 0.06, 0], [784, 0.06, 0], [1047, 0.12, 0]], 0.45)
	_streams["colonize"] = _build([[523, 0.1, 1], [659, 0.1, 1], [784, 0.1, 1], [1047, 0.25, 1], [784, 0.08, 1], [1047, 0.3, 1]], 0.5)
	_streams["hit"] = _build([[160, 0.12, 1], [120, 0.15, 1]], 0.3)
	_streams["select"] = _build([[880, 0.03, 0]], 0.25)
	_streams["boss"] = _build([[110, 0.2, 0], [138, 0.2, 0], [110, 0.2, 0], [92, 0.4, 0]], 0.45)


## Joue un effet. `pitch` permet de monter le son avec le combo.
func play(name: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if not enabled or not _streams.has(name):
		return
	var p: AudioStreamPlayer = _players[_next_player]
	_next_player = (_next_player + 1) % POOL_SIZE
	p.stream = _streams[name]
	p.pitch_scale = pitch
	p.volume_db = volume_db
	p.play()


## Construit un AudioStreamWAV 16 bits mono à partir d'une séquence de notes
## [fréquence Hz, durée s, forme (0 = carrée, 1 = triangle)].
func _build(notes: Array, amplitude: float) -> AudioStreamWAV:
	var samples := PackedByteArray()
	for note in notes:
		var freq: float = note[0]
		var length: int = int(note[1] * SAMPLE_RATE)
		var shape: int = note[2]
		for i in range(length):
			var t := float(i) / SAMPLE_RATE
			var phase := fmod(t * freq, 1.0)
			var v: float
			if shape == 0:
				v = 1.0 if phase < 0.5 else -1.0
			else:
				v = 4.0 * absf(phase - 0.5) - 1.0
			# Enveloppe : attaque courte, décroissance linéaire.
			var env := minf(1.0, float(i) / 60.0) * (1.0 - float(i) / float(length))
			var s := int(clampf(v * env * amplitude, -1.0, 1.0) * 32767.0)
			samples.append(s & 0xFF)
			samples.append((s >> 8) & 0xFF)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = samples
	return stream
