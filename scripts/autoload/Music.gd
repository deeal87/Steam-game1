extends Node
## Synthesised score.
##
## Eight layers, all the same length and tempo, all generated at boot. They play
## in sync from the moment the shift starts and are never stopped while a scene
## is running, so they stay in phase with each other for the whole night. Only
## their volumes ever change.
##
## What makes this an arrangement rather than a mix is the **section**. The score
## has four of them — settled, working, wary, bad — and each one names a
## different set of layers. Sections move **one step at a time, on a bar line**,
## so the music builds and unwinds in a musical order instead of crossfading
## wherever the tension happens to land. Climbing has a higher threshold than
## falling, so a single tense moment does not make the score flap.
##
## On top of that the score knows two things that have nothing to do with
## tension: **which night it is**, which biases the whole thing upward so night
## ten never sounds as calm as night one, and **how far through the shift you
## are**, which thins the pad out and brings the sub up as it gets late.
##
## One rule governs what the music is allowed to know: **it must never react to
## whether somebody is police.** A sting when an officer walks in would hand the
## player the answer the whole game is built around withholding. Tension is
## driven only by things the player can already see — the heat meter, a customer
## having asked for what is under the counter, a raid, the tunnels. The night
## number and the clock are on screen too, so those are fair game.

const RATE := 22050
const BPM := 68.0
const BARS := 4
const BEATS := BARS * 4

## Semitone offsets from A, natural minor. The whole score sits in one scale so
## the layers can never disagree with each other.
const SCALE := [0, 2, 3, 5, 7, 8, 10]
const ROOT := 110.0   ## A2

## Layer name -> resting volume when a section calls for it at full strength.
const BASE := {
	"bed": -10.0, "bed_dark": -10.0,
	"pulse": -13.0, "pulse_dense": -14.0,
	"motif": -15.0, "dread": -12.0, "deep": -11.0, "strain": -16.0,
}

## What each section is made of, as trims from the resting volume above.
## A layer that is not named is silent in that section.
const SECTIONS: Array[Dictionary] = [
	{"bed": 0.0},                                                    # 0 · settled
	{"bed": -1.0, "pulse": -3.0},                                    # 1 · working
	{"bed_dark": 0.0, "pulse": 0.0, "motif": -2.0},                  # 2 · wary
	{"bed_dark": -1.0, "pulse_dense": 0.0, "motif": 0.0,
		"dread": -4.0, "strain": -3.0},                              # 3 · bad
]

## Tension needed to climb into section 1, 2, 3 — and the lower tension needed
## before it will fall back out again. The gap is the hysteresis.
const CLIMB := [0.14, 0.42, 0.72]
const FALL := [0.06, 0.28, 0.56]

const SILENT := -60.0
## Fast enough that a section change reads as the arrangement moving rather than
## two arrangements briefly playing at once — about half a bar to cross.
const FADE_DB_PER_SEC := 24.0

## The mixer bus every layer plays on, so the music slider moves all of them
## together. An identifier, not a word on screen — the slider beside it in the
## menu happens to be spelled the same and is not the same thing.
const BUS := "Music"

var _layers: Dictionary = {}     ## name -> {player, target, base, current}
var _bus := -1
var _playing := false
var _tension := 0.0
var _scene := ""
var _section := 0
var _bar_clock := 0.0
var _night_bias := 0.0
var _progress := 0.0


func _ready() -> void:
	_make_bus()
	for name: String in BASE:
		var p := AudioStreamPlayer.new()
		p.bus = BUS
		p.stream = _build(name)
		p.volume_db = SILENT
		add_child(p)
		_layers[name] = {"player": p, "target": SILENT, "base": float(BASE[name]),
			"current": SILENT}


func _make_bus() -> void:
	_bus = AudioServer.bus_count
	AudioServer.add_bus(_bus)
	AudioServer.set_bus_name(_bus, BUS)
	AudioServer.set_bus_send(_bus, "Master")


func _process(delta: float) -> void:
	if _playing and _scene == "shift":
		_advance_bar_clock(delta)
	for name: String in _layers:
		var layer: Dictionary = _layers[name]
		var current: float = layer["current"]
		var target: float = layer["target"]
		var p: AudioStreamPlayer = layer["player"]
		if absf(current - target) >= 0.1:
			current = move_toward(current, target, delta * FADE_DB_PER_SEC)
			layer["current"] = current
			p.volume_db = current
		# Players are only ever stopped once the whole score has faded out — and
		# a layer sitting silent inside a section has to be stopped too, or it
		# keeps mixing into a scene that has ended. Stopping one *mid*-scene is
		# what must never happen: it would restart from zero and fall out of
		# phase with the seven that kept running.
		if not _playing and current <= SILENT + 0.5 and p.playing:
			p.stop()


## Sections only ever change on a bar line, and only by one step. Everything
## about the arrangement moving in order depends on this being the single place
## `_section` is written to during a shift.
func _advance_bar_clock(delta: float) -> void:
	_bar_clock -= delta
	if _bar_clock > 0.0:
		return
	_bar_clock = bar_seconds()
	var wanted := wanted_section(_section, _tension + _night_bias)
	if wanted != _section:
		_section = wanted
		_apply()


func bar_seconds() -> float:
	return 60.0 / BPM * 4.0


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
		_layers[name]["target"] = SILENT


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


## Where the arrangement wants to be, given where it already is. Climbing needs
## more tension than staying, and it only ever moves one step, so the score
## walks up and down the sections instead of jumping between them.
static func wanted_section(from: int, tension: float) -> int:
	var s: int = clampi(from, 0, SECTIONS.size() - 1)
	if s < SECTIONS.size() - 1 and tension >= CLIMB[s]:
		return s + 1
	if s > 0 and tension < FALL[s - 1]:
		return s - 1
	return s


## 0 is a quiet night, 1 is as wound up as the shift gets. Driven by heat and by
## a customer having made the ask — both things the player can already see.
func set_tension(value: float) -> void:
	_tension = clampf(value, 0.0, 1.0)
	# Note the absence of an `_apply()` here. Tension picks the *destination*;
	# the bar clock decides when the arrangement is allowed to move there.


## Later nights sit higher in the arrangement than early ones, so the shift
## never opens as quietly on night ten as it did on night one. The player can
## see the night number, so the score is not giving anything away by knowing it.
func set_night(night: int) -> void:
	_night_bias = clampf(float(night - 1) * 0.035, 0.0, 0.30)


## How far through the shift we are, 0 at 23:00 and 1 at 05:00. Late on, the pad
## thins out and the sub comes up — the small hours sound emptier and heavier.
func set_progress(value: float) -> void:
	_progress = clampf(value, 0.0, 1.0)
	if _playing:
		_apply()


## Everything starts together and stays running for the whole scene. A layer
## that is inaudible is still playing at -60dB rather than stopped, because a
## stopped player restarts at zero and would be out of phase with the rest.
func _start_all() -> void:
	if _playing:
		return
	_playing = true
	_section = 0 if _scene == "shift" else _section
	_bar_clock = bar_seconds()
	for name: String in _layers:
		var p: AudioStreamPlayer = _layers[name]["player"]
		p.volume_db = SILENT
		_layers[name]["current"] = SILENT
		p.play()


func _apply() -> void:
	var mix := {}
	match _scene:
		"shift":
			var section: Dictionary = SECTIONS[clampi(_section, 0, SECTIONS.size() - 1)]
			for name: String in section:
				mix[name] = _base(name) + float(section[name]) + _hour_trim(name)
		"raid":
			# No sections here. The raid is one fixed arrangement at full tilt,
			# because there is nothing left to be subtle about.
			mix["bed_dark"] = _base("bed_dark") - 6.0
			mix["pulse_dense"] = _base("pulse_dense")
			mix["dread"] = _base("dread")
			mix["strain"] = _base("strain")
		"sewer":
			mix["deep"] = _base("deep")
			mix["dread"] = _base("dread") - 14.0
			mix["strain"] = _base("strain") - 8.0
	for name: String in _layers:
		_layers[name]["target"] = float(mix.get(name, SILENT))


## The hour of the night, as a volume trim. Pads recede, weight arrives.
func _hour_trim(name: String) -> float:
	match name:
		"bed", "bed_dark": return -4.5 * _progress
		"deep": return 3.0 * _progress
		"motif": return -2.0 * _progress
	return 0.0


func _base(name: String) -> float:
	return float(_layers[name]["base"])


func section() -> int:
	return _section


# --- Synthesis ---------------------------------------------------------------

func _beat_samples() -> int:
	return int(60.0 / BPM * RATE)


func _loop_samples() -> int:
	return _beat_samples() * BEATS


func _note(semitone: int, octave: int = 0) -> float:
	return ROOT * pow(2.0, (float(semitone) + float(octave) * 12.0) / 12.0)


func _build(name: String) -> AudioStreamWAV:
	match name:
		"bed": return _bed([[0, 3, 7], [-4, 0, 3], [3, 7, 10], [-2, 2, 5]])
		# Am, F, Dm, E — the same opening two bars, then it turns. That E is a
		# major chord in a minor key, and the G# in it is why the dark bed feels
		# like it is leaning on you.
		"bed_dark": return _bed([[0, 3, 7], [-4, 0, 3], [5, 8, 12], [7, 11, 14]])
		"pulse": return _pulse(false)
		"pulse_dense": return _pulse(true)
		"motif": return _motif()
		"dread": return _dread()
		"deep": return _deep()
		"strain": return _strain()
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


## Low sustained root notes under a slow detuned pad. One chord per bar. Which
## four chords decides whether this is the shop being open and nothing happening
## yet, or the same shop an hour later.
func _bed(chords: Array) -> AudioStreamWAV:
	var n := _loop_samples()
	var out := PackedFloat32Array()
	out.resize(n)
	var beat := _beat_samples()

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
## makes the night feel like it is counting. The dense version doubles the rate
## and stops limping, which is the single clearest signal the score can give
## that things have got away from you.
func _pulse(dense: bool) -> AudioStreamWAV:
	var n := _loop_samples()
	var out := PackedFloat32Array()
	out.resize(n)
	var beat := _beat_samples()
	var div := 4 if dense else 2
	var step_len := int(beat / div)

	for step in BEATS * div:
		# The loose version skips a couple of steps per bar so it limps rather
		# than marches. The dense one hits everything.
		if not dense and (step % 8 == 5 or step % 8 == 7):
			continue
		var start := step * step_len
		var length := int(step_len * 0.9)
		var accent: float = 1.0 if step % (div * 2) == 0 else 0.62
		for i in length:
			var idx := start + i
			if idx >= n:
				break
			var t := float(i) / RATE
			var e := _env(t, float(length) / RATE, 0.004, 3.2)
			# Pitch drops through the hit, which is what makes it a thud.
			var f := _note(0, -2) * (1.0 + 0.5 * pow(1.0 - t * 12.0, 2.0) if t < 0.08 else 1.0)
			out[idx] += sin(f * t * TAU) * e * 0.55 * accent * (0.8 if dense else 1.0)
	return _wrap(out)


## A three-note falling cell, plucked, twice a bar, starting a step lower each
## time round. It is the only thing in the score with a tune, which is the point:
## once it arrives you can hear the night going somewhere.
func _motif() -> AudioStreamWAV:
	var n := _loop_samples()
	var out := PackedFloat32Array()
	out.resize(n)
	var beat := _beat_samples()
	var cell := [7, 5, 3]        ## E D C
	var descent := [0, 0, -2, -3]  ## and the cell itself sinks as the loop turns

	for bar in BARS:
		var shift: int = descent[bar % descent.size()]
		for rep: int in [0, 1]:
			var anchor := bar * beat * 4 + rep * beat * 2 + int(beat * 0.5)
			for k in cell.size():
				var start := anchor + k * int(beat * 0.5)
				var length := int(beat * 0.9)
				var f := _note(int(cell[k]) + shift)
				for i in length:
					var idx := start + i
					if idx >= n:
						break
					var t := float(i) / RATE
					var e := _env(t, float(length) / RATE, 0.003, 4.0)
					# Sine plus a weak third harmonic: enough edge to cut through
					# the pad without turning into a lead instrument.
					out[idx] += (sin(f * t * TAU) * 0.7
						+ sin(f * 3.0 * t * TAU) * 0.12) * e * 0.30
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


## Tremolo, on the fifth, creeping up a semitone across the loop and dropping
## back at the top. Strings that cannot hold still.
func _strain() -> AudioStreamWAV:
	var n := _loop_samples()
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var k := float(i) / float(n)
		# A semitone of drift over four bars is slow enough that you feel it
		# before you notice it.
		var f := _note(7) * pow(2.0, k / 12.0)
		phase += f / RATE
		var saw := fmod(phase, 1.0) * 2.0 - 1.0
		var trem := 0.55 + 0.45 * sin(t * 11.0 * TAU)
		# Swells in from nothing over the first bar so it never enters as a cut.
		var swell: float = clampf(k * 4.0, 0.0, 1.0)
		out[i] = saw * 0.20 * trem * swell
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
