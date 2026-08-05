extends Node
## Synthesises every sound in the game at boot.
##
## No .wav or .ogg files ship with this project. Each cue is written into a
## buffer as raw 16-bit PCM the first time it is asked for, then cached.

const RATE := 22050
## Its own bus, so effects can be turned down without touching the music and
## vice versa. Everything used to play straight onto Master, which meant the
## only way to quieten a gunshot was to quieten the whole game.
const BUS := "SFX"

## How far a world sound carries. The shop is ten metres across and the street a
## hundred, so this is generous enough to hear a raid forming up outside and
## tight enough that a gunshot at the far end of the sewer is not in your ear.
const WORLD_MAX_DISTANCE := 34.0

var _cache: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _world_players: Array[AudioStreamPlayer3D] = []
var _next_player: int = 0
var _next_world: int = 0
var _ambience: AudioStreamPlayer
var _bus_index: int = 0


func _ready() -> void:
	_make_bus()
	# A small pool so overlapping cues do not cut each other off.
	for i in 12:
		var p := AudioStreamPlayer.new()
		p.bus = BUS
		add_child(p)
		_players.append(p)

	# A second pool that exists in space. Positional audio is not decoration
	# here: the sewer is pitch dark, so which direction a thing is coming from
	# is the only information you get about it, and a raid you can hear forming
	# up on your left is a raid you can prepare for.
	for i in 10:
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = BUS
		p3.max_distance = WORLD_MAX_DISTANCE
		p3.unit_size = 4.0
		# Inverse-square falloff, which is what real sound does and what makes
		# distance readable rather than merely quieter.
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
		add_child(p3)
		_world_players.append(p3)

	_ambience = AudioStreamPlayer.new()
	_ambience.bus = BUS
	_ambience.volume_db = -20.0
	add_child(_ambience)


## Moves the positional pool into the viewport the 3D camera lives in.
##
## This is not optional and it is easy to miss. An AudioStreamPlayer3D resolves
## its listener from *its own* viewport, and the 3D world here renders into a
## SubViewport while this autoload sits under the root. Left where they are
## built, every positional sound would look for a listener in a viewport that
## contains no 3D camera at all — and the failure is silence, which is
## indistinguishable from a sound simply not having been triggered.
func attach_to_world(host: Node) -> void:
	if host == null or not is_instance_valid(host):
		return
	for p in _world_players:
		if p.get_parent() == host:
			continue
		p.get_parent().remove_child(p)
		host.add_child(p)


## Where the positional pool currently lives, so a test can check it is
## somewhere a listener can hear it.
func world_pool_viewport() -> Viewport:
	if _world_players.is_empty():
		return null
	return _world_players[0].get_viewport()


func _make_bus() -> void:
	if AudioServer.get_bus_index(BUS) >= 0:
		_bus_index = AudioServer.get_bus_index(BUS)
		return
	_bus_index = AudioServer.bus_count
	AudioServer.add_bus(_bus_index)
	AudioServer.set_bus_name(_bus_index, BUS)
	AudioServer.set_bus_send(_bus_index, "Master")


func set_volume(linear: float) -> void:
	if _bus_index <= 0:
		return
	AudioServer.set_bus_volume_db(_bus_index, linear_to_db(clampf(linear, 0.0001, 1.0)))
	AudioServer.set_bus_mute(_bus_index, linear <= 0.001)


## A sound with no place in the world: interface, and things happening in your
## own hands.
func play(cue: String, volume_db: float = -8.0, pitch: float = 1.0) -> void:
	var stream := _cue(cue)
	if stream == null:
		return
	var p := _free_player()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(0.94, 1.06)
	p.play()


## A sound that happens somewhere. Falls back to the flat pool when there is no
## position to give it, so a caller never has to check.
func play_at(cue: String, at: Vector3, volume_db: float = -8.0, pitch: float = 1.0) -> void:
	var stream := _cue(cue)
	if stream == null:
		return
	if _world_players.is_empty():
		play(cue, volume_db, pitch)
		return
	var p := _free_world_player()
	p.stream = stream
	p.global_position = at
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(0.94, 1.06)
	p.play()


## Prefers a player that is not already busy, and only steals the oldest one
## when they are all in use.
##
## Plain round-robin advanced regardless, so a burst of interface clicks could
## cut off a gunshot that was still sounding while three idle players sat there.
func _free_player() -> AudioStreamPlayer:
	for i in _players.size():
		var idx := (_next_player + i) % _players.size()
		if not _players[idx].playing:
			_next_player = (idx + 1) % _players.size()
			return _players[idx]
	var p := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	return p


func _free_world_player() -> AudioStreamPlayer3D:
	for i in _world_players.size():
		var idx := (_next_world + i) % _world_players.size()
		if not _world_players[idx].playing:
			_next_world = (idx + 1) % _world_players.size()
			return _world_players[idx]
	var p := _world_players[_next_world]
	_next_world = (_next_world + 1) % _world_players.size()
	return p


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
