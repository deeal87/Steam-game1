extends Node
## Synthesised score.
##
## Four layers, all the same length and tempo, all generated at boot. They play
## in sync from the moment the shift starts and are mixed by fading their
## volumes, so moving between calm and dread is a crossfade rather than a cut.
##
## One rule governs what the music is allowed to know: **it must never react to
## whether somebody is police.** A sting when an officer walks in would hand the
## player the answer the whole game is built around withholding. Tension is
## driven only by things the player can already see — the heat meter, a customer
## having asked for what is under the counter, a raid, the tunnels.

const RATE := 22050
const BPM := 68.0
const BARS := 4
const BEATS := BARS * 4

## Semitone offsets from A, natural minor. The whole score sits in one scale so
## the layers can never disagree with each other.
const SCALE := [0, 2, 3, 5, 7, 8, 10]
const ROOT := 110.0   ## A2

var _layers: Dictionary = {}     ## name -> {player, target, current}
var _bus := -1
var _playing := false
var _tension := 0.0
var _scene := ""


func _ready() -> void:
	_make_bus()
	for conf: Array in [
		["bed", -10.0], ["pulse", -13.0], ["dread", -12.0], ["deep", -11.0],
	]:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.stream = _build(conf[0])
		p.volume_db = -60.0
		add_child(p)
		_layers[conf[0]] = {"player": p, "target": -60.0, "base": conf[1], "current": -60.0}


func _make_bus() -> void:
	_bus = AudioServer.bus_count
	AudioServer.add_bus(_bus)
	AudioServer.set_bus_name(_bus, "Music")
	AudioServer.set_bus_send(_bus, "Master")


func _process(delta: float) -> void:
	# Fades are slow on purpose: the score should change under you without you
	# noticing the moment it did.
	for name: String in _layers:
		var layer: Dictionary = _layers[name]
		var current: float = layer["current"]
		var target: float = layer["target"]
		if absf(current - target) < 0.1:
			continue
		current = move_toward(current, target, delta * 9.0)
		layer["current"] = current
		var p: AudioStreamPlayer = layer["player"]
		p.volume_db = current
		if current <= -55.0 and p.playing and target <= -55.0:
			p.stop()


# --- What is playing ---------------------------------------------------------

func play_shift() -> void:
	_scene = "shift"
	_start_all()
	_apply()


func play_raid() -> void:
	_scene = "raid"
	_start_all()
	_apply()


func play_sewer() -> void:
	_scene = "sewer"
	_start_all()
	_apply()


func stop_all() -> void:
	_scene = ""
	_playing = false
	for name: String in _layers:
		_layers[name]["target"] = -60.0


## Works out how wound up the night is from the things the player can already
## see on their own screen.
##
## Deliberately takes no argument that could distinguish an officer from a
## civilian. That is not an oversight to be tidied up later — if this function
## ever learns who is police, the score answers the question the entire game is
## built on withholding.
static func tension_from(heat: float, asked_for_illicit: bool, already_sold: bool,
		evidence: int) -> float:
	var t := clampf(heat, 0.0, 100.0) / 100.0 * 0.65
	if asked_for_illicit and not already_sold:
		t += 0.45
	if evidence > 0:
		t += 0.25
	return clampf(t, 0.0, 1.0)


## 0 is a quiet night, 1 is as wound up as the shift gets. Driven by heat and by
## a customer having made the ask — both things the player can already see.
func set_tension(value: float) -> void:
	_tension = clampf(value, 0.0, 1.0)
	if _playing:
		_apply()


## All four start together and stay in sync; only their volumes ever change.
func _start_all() -> void:
	if _playing:
		return
	_playing = true
	for name: String in _layers:
		var p: AudioStreamPlayer = _layers[name]["player"]
		if not p.playing:
			p.play()


func _apply() -> void:
	var mix := {"bed": -60.0, "pulse": -60.0, "dread": -60.0, "deep": -60.0}
	match _scene:
		"shift":
			mix["bed"] = _base("bed")
			# The pulse only really arrives once the night has some heat in it.
			if _tension > 0.05:
				mix["pulse"] = _base("pulse") - (1.0 - _tension) * 16.0
			if _tension > 0.6:
				mix["dread"] = _base("dread") - (1.0 - _tension) * 30.0
		"raid":
			mix["bed"] = _base("bed") - 6.0
			mix["pulse"] = _base("pulse")
			mix["dread"] = _base("dread")
		"sewer":
			mix["deep"] = _base("deep")
			mix["dread"] = _base("dread") - 14.0
	for name: String in mix:
		_layers[name]["target"] = mix[name]


func _base(name: String) -> float:
	return float(_layers[name]["base"])


# --- Synthesis ---------------------------------------------------------------

func _beat_samples() -> int:
	return int(60.0 / BPM * RATE)


func _loop_samples() -> int:
	return _beat_samples() * BEATS


func _note(semitone: int, octave: int = 0) -> float:
	return ROOT * pow(2.0, (float(semitone) + float(octave) * 12.0) / 12.0)


func _build(name: String) -> AudioStreamWAV:
	match name:
		"bed": return _bed()
		"pulse": return _pulse()
		"dread": return _dread()
		"deep": return _deep()
	return null


func _wrap(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = samples.size()
	return s


## Envelope: quick attack, long decay, no sustain to speak of. Everything in
## this score is a thing that was struck once and is dying away.
func _env(t: float, length: float, attack: float, release: float) -> float:
	if t < attack:
		return t / attack
	var k := (t - attack) / maxf(0.001, length - attack)
	return pow(1.0 - clampf(k, 0.0, 1.0), release)


## Low sustained root notes under a slow detuned pad. This is the sound of the
## shop being open and nothing happening yet.
func _bed() -> AudioStreamWAV:
	var n := _loop_samples()
	var out := PackedFloat32Array()
	out.resize(n)
	var beat := _beat_samples()

	# One chord per bar: Am, F, C, G — the most ordinary sad progression there
	# is, which is right for a place like this.
	var chords := [[0, 3, 7], [-4, 0, 3], [3, 7, 10], [-2, 2, 5]]
	for bar in BARS:
		var chord: Array = chords[bar % chords.size()]
		var start := bar * beat * 4
		var length := beat * 4
		for i in length:
			var idx := start + i
			if idx >= n:
				break
			var t := float(i) / RATE
			var secs := float(length) / RATE
			var e := _env(t, secs, 0.45, 1.3)
			var v := 0.0
			# Bass: the root, an octave down, plain sine so it stays out of the way.
			v += sin(_note(chord[0], -1) * t * TAU) * 0.55
			# Pad: the triad, slightly detuned against itself so it breathes.
			for s: int in chord:
				var f := _note(s)
				v += (absf(fmod(f * t, 1.0) * 4.0 - 2.0) - 1.0) * 0.12
				v += (absf(fmod(f * 1.004 * t, 1.0) * 4.0 - 2.0) - 1.0) * 0.10
			out[idx] += v * e * 0.30
	return _wrap(out)


## An eighth-note heartbeat low in the mix. It does not play a tune; it just
## makes the night feel like it is counting.
func _pulse() -> AudioStreamWAV:
	var n := _loop_samples()
	var out := PackedFloat32Array()
	out.resize(n)
	var beat := _beat_samples()
	var eighth := int(beat / 2)

	for step in BEATS * 2:
		# Skip a couple of steps per bar so it limps rather than marches.
		if step % 8 == 5 or step % 8 == 7:
			continue
		var start := step * eighth
		var length := int(eighth * 0.9)
		var accent: float = 1.0 if step % 4 == 0 else 0.62
		for i in length:
			var idx := start + i
			if idx >= n:
				break
			var t := float(i) / RATE
			var e := _env(t, float(length) / RATE, 0.004, 3.2)
			# Pitch drops through the hit, which is what makes it a thud.
			var f := _note(0, -2) * (1.0 + 0.5 * pow(1.0 - t * 12.0, 2.0) if t < 0.08 else 1.0)
			out[idx] += sin(f * t * TAU) * e * 0.55 * accent
	return _wrap(out)


## A high, sour, wavering tone. Two notes a semitone apart, which is the
## cheapest way to make a listener uncomfortable.
func _dread() -> AudioStreamWAV:
	var n := _loop_samples()
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var slow := 0.5 + 0.5 * sin(t * 0.11 * TAU)
		var a := sin(_note(0, 1) * t * TAU)
		var b := sin(_note(1, 1) * t * TAU)
		# Amplitude wanders so it never settles into something you can ignore.
		out[i] = (a * 0.5 + b * 0.4) * 0.16 * (0.35 + 0.65 * slow)
	return _wrap(out)


## Underground. Almost no pitch at all, just weight and the occasional drip.
func _deep() -> AudioStreamWAV:
	var n := _loop_samples()
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var last := 0.0

	for i in n:
		var t := float(i) / RATE
		var sub := sin(_note(0, -2) * t * TAU) * 0.42
		sub += sin(_note(7, -2) * 1.002 * t * TAU) * 0.16
		last = lerpf(last, rng.randf_range(-1.0, 1.0), 0.008)
		out[i] = (sub + last * 0.22) * 0.42

	# Drips, at irregular intervals, each a short falling ping.
	for d in 9:
		var at := int(rng.randf_range(0.0, 1.0) * float(n - RATE))
		var length := int(RATE * 0.35)
		var pitch := rng.randf_range(700.0, 1500.0)
		for i in length:
			var idx := at + i
			if idx >= n:
				break
			var t := float(i) / RATE
			var e := _env(t, float(length) / RATE, 0.002, 5.0)
			out[idx] += sin(pitch * (1.0 - t * 0.5) * t * TAU) * e * 0.10
	return _wrap(out)


# --- Settings ----------------------------------------------------------------

func set_volume(linear: float) -> void:
	if _bus < 0:
		return
	AudioServer.set_bus_volume_db(_bus, linear_to_db(clampf(linear, 0.0001, 1.0)))
	AudioServer.set_bus_mute(_bus, linear <= 0.001)
