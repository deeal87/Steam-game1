extends Node
## Synthesises every sound in the game at boot.
##
## No .wav or .ogg files ship with this project. Each cue is written into a
## buffer as raw 16-bit PCM the first time it is asked for, then cached.

const RATE := 22050

var _cache: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_player: int = 0
var _ambience: AudioStreamPlayer


func _ready() -> void:
	# A small pool so overlapping cues do not cut each other off.
	for i in 12:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	_ambience = AudioStreamPlayer.new()
	_ambience.bus = "Master"
	_ambience.volume_db = -20.0
	add_child(_ambience)


func play(cue: String, volume_db: float = -8.0, pitch: float = 1.0) -> void:
	var stream := _cue(cue)
	if stream == null:
		return
	var p := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(0.94, 1.06)
	p.play()


func start_ambience() -> void:
	if _ambience.playing:
		return
	_ambience.stream = _cue("ambience")
	_ambience.play()


func stop_ambience() -> void:
	_ambience.stop()


## Named `_cue` rather than `_get` because Object already defines `_get`.
func _cue(cue: String) -> AudioStreamWAV:
	if not _cache.has(cue):
		_cache[cue] = _build(cue)
	return _cache[cue]


func _build(cue: String) -> AudioStreamWAV:
	match cue:
		"beep":      return _tone(880.0, 0.06, 0.35, "square")
		"beep_low":  return _tone(320.0, 0.10, 0.35, "square")
		"deny":      return _sweep(420.0, 140.0, 0.22, 0.4, "square")
		"confirm":   return _sweep(500.0, 900.0, 0.14, 0.35, "square")
		"click":     return _noise(0.02, 0.30, 6000.0)
		"chime":     return _chime()
		"register":  return _register()
		"gunshot":   return _gunshot()
		"shotgun":   return _shotgun()
		"swing":     return _sweep(200.0, 90.0, 0.18, 0.35, "sine")
		"impact":    return _noise(0.13, 0.55, 900.0)
		"footstep":  return _noise(0.07, 0.16, 1400.0)
		"scanner":   return _scanner()
		"typing":    return _noise(0.025, 0.20, 4200.0)
		"radio":     return _noise(0.45, 0.16, 2600.0)
		"heartbeat": return _heartbeat()
		"breach":    return _noise(0.55, 0.75, 300.0)
		"ambience":  return _ambience_bed()
	return null


# --- Primitives --------------------------------------------------------------

func _wrap(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = samples.size()
	return s


func _osc(phase: float, shape: String) -> float:
	match shape:
		"square": return 1.0 if fmod(phase, 1.0) < 0.5 else -1.0
		"saw":    return fmod(phase, 1.0) * 2.0 - 1.0
		"tri":    return absf(fmod(phase, 1.0) * 4.0 - 2.0) - 1.0
	return sin(phase * TAU)


func _tone(freq: float, dur: float, amp: float, shape: String) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env: float = minf(1.0, float(i) / 80.0) * pow(1.0 - float(i) / n, 1.6)
		out[i] = _osc(freq * t, shape) * amp * env
	return _wrap(out)


func _sweep(f0: float, f1: float, dur: float, amp: float, shape: String) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var k := float(i) / n
		phase += lerpf(f0, f1, k) / RATE
		out[i] = _osc(phase, shape) * amp * pow(1.0 - k, 1.4)
	return _wrap(out)


## One-pole low pass keeps the noise bursts from sounding like plain static.
func _noise(dur: float, amp: float, cutoff: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var a: float = clampf(cutoff / float(RATE), 0.0, 1.0)
	var last := 0.0
	for i in n:
		last = lerpf(last, randf_range(-1.0, 1.0), a)
		out[i] = last * amp * pow(1.0 - float(i) / n, 1.8)
	return _wrap(out)


# --- Composites --------------------------------------------------------------

func _chime() -> AudioStreamWAV:
	var n := int(0.9 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := pow(1.0 - float(i) / n, 2.5)
		out[i] = (sin(1046.0 * t * TAU) * 0.5 + sin(1568.0 * t * TAU) * 0.3) * 0.3 * env
	return _wrap(out)


func _register() -> AudioStreamWAV:
	var n := int(0.5 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := pow(1.0 - float(i) / n, 2.0)
		var bell := sin(1200.0 * t * TAU) * 0.4 + sin(1810.0 * t * TAU) * 0.25
		var clack := randf_range(-1.0, 1.0) * (0.5 if i < 900 else 0.0)
		out[i] = (bell * env + clack * 0.35) * 0.35
	return _wrap(out)


func _gunshot() -> AudioStreamWAV:
	var n := int(0.34 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var last := 0.0
	for i in n:
		var k := float(i) / n
		last = lerpf(last, randf_range(-1.0, 1.0), 0.55)
		var crack: float = last * pow(1.0 - k, 6.0)
		var body := sin(float(i) / RATE * 95.0 * TAU) * pow(1.0 - k, 3.0) * 0.5
		out[i] = clampf((crack + body) * 0.85, -1.0, 1.0)
	return _wrap(out)


func _shotgun() -> AudioStreamWAV:
	var n := int(0.5 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var last := 0.0
	for i in n:
		var k := float(i) / n
		last = lerpf(last, randf_range(-1.0, 1.0), 0.30)
		var body := sin(float(i) / RATE * 62.0 * TAU) * pow(1.0 - k, 2.4) * 0.65
		out[i] = clampf((last * pow(1.0 - k, 4.0) + body) * 0.95, -1.0, 1.0)
	return _wrap(out)


func _scanner() -> AudioStreamWAV:
	var n := int(0.75 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		# Rising warble, like something sweeping across a body.
		var f := 500.0 + 260.0 * sin(t * 11.0) + 300.0 * t
		out[i] = _osc(f * t, "tri") * 0.16 * minf(1.0, (1.0 - float(i) / n) * 3.0)
	return _wrap(out)


func _heartbeat() -> AudioStreamWAV:
	var n := int(1.0 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var thump := 0.0
		for onset: float in [0.0, 0.30]:
			if t >= onset and t < onset + 0.18:
				var k := (t - onset) / 0.18
				thump += sin((t - onset) * 55.0 * TAU) * pow(1.0 - k, 3.0)
		out[i] = thump * 0.55
	return _wrap(out)


## A slow detuned drone with wind on top. Loops seamlessly because both
## component frequencies complete whole cycles over the buffer length.
func _ambience_bed() -> AudioStreamWAV:
	var seconds := 8.0
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var last := 0.0
	for i in n:
		var t := float(i) / RATE
		var drone := sin(55.0 * t * TAU) * 0.28 + sin(55.5 * t * TAU) * 0.22
		drone += sin(82.5 * t * TAU) * 0.10
		last = lerpf(last, randf_range(-1.0, 1.0), 0.02)
		var wind: float = last * (0.30 + 0.18 * sin(t * 0.25 * TAU))
		out[i] = (drone * 0.5 + wind) * 0.55
	return _wrap(out, true)
