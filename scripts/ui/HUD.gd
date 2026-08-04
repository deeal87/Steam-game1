class_name HUD
extends CanvasLayer
## The permanently-visible layer: takings, the clock, what you are looking at,
## and whatever the person at the hatch just said.

const NOTICE_LIFETIME := 5.5
const METER_W := 160
const MAX_NOTICES := 5

var _clock_label: Label
var _money_label: Label
var _night_label: Label
var _quota_label: Label
var _heat_bar: Control
var _heat_box: HBoxContainer
var _health_bar: Control
var _health_box: HBoxContainer
var _prompt: Label
var _notice_col: VBoxContainer
var _subtitle: Label
var _subtitle_timer: float = 0.0
var _crosshair: Control
var _hands: Label
var _notices: Array[Dictionary] = []
var _player: Player


func _ready() -> void:
	layer = 5
	_build()
	Signals.prompt_changed.connect(_on_prompt)
	Signals.notice.connect(_on_notice)
	Signals.customer_spoke.connect(_on_spoke)
	Signals.money_changed.connect(func(_m: int) -> void: _refresh_stats())
	Signals.heat_changed.connect(func(_h: float) -> void: _refresh_stats())
	Signals.shift_clock.connect(_on_clock)
	Signals.quota_changed.connect(func(_c: int, _t: int) -> void: _refresh_stats())
	_refresh_stats()


func bind_player(p: Player) -> void:
	_player = p


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# --- Top left: the numbers that decide whether you survive the month ---
	var tl := VBoxContainer.new()
	tl.position = Vector2(26, 18)
	tl.add_theme_constant_override("separation", 2)
	root.add_child(tl)
	_night_label = UIKit.label("NIGHT 1", UIKit.FONT_M, UIKit.GREEN)
	_clock_label = UIKit.label("23:00", UIKit.FONT_L, UIKit.WHITE)
	_money_label = UIKit.label("0", UIKit.FONT_M, UIKit.GREEN)
	_quota_label = UIKit.label("rent 110", UIKit.FONT_S, UIKit.GREEN_DIM)
	tl.add_child(_night_label)
	tl.add_child(_clock_label)
	tl.add_child(_money_label)
	tl.add_child(_quota_label)

	# --- Top right: heat and health ---
	var tr := VBoxContainer.new()
	tr.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tr.position = Vector2(-268, 20)
	tr.add_theme_constant_override("separation", 4)
	root.add_child(tr)

	_heat_box = HBoxContainer.new()
	_heat_box.add_theme_constant_override("separation", 6)
	_heat_box.add_child(UIKit.label("HEAT", UIKit.FONT_S, UIKit.GREEN_DIM))
	_heat_bar = UIKit.meter(0, 100, METER_W, UIKit.AMBER)
	_heat_box.add_child(_heat_bar)
	tr.add_child(_heat_box)

	_health_box = HBoxContainer.new()
	_health_box.add_theme_constant_override("separation", 6)
	_health_box.add_child(UIKit.label("BODY", UIKit.FONT_S, UIKit.GREEN_DIM))
	_health_bar = UIKit.meter(100, 100, METER_W, UIKit.RED)
	_health_box.add_child(_health_bar)
	tr.add_child(_health_box)

	_hands = UIKit.label("", UIKit.FONT_S, UIKit.GREEN_DIM)
	_hands.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tr.add_child(_hands)

	# --- Notices, bottom left ---
	_notice_col = VBoxContainer.new()
	_notice_col.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_notice_col.position = Vector2(26, -210)
	_notice_col.custom_minimum_size = Vector2(520, 0)
	_notice_col.add_theme_constant_override("separation", 2)
	root.add_child(_notice_col)

	# --- Subtitle, centred low: what the customer is saying ---
	_subtitle = UIKit.label("", UIKit.FONT_M, UIKit.WHITE)
	# Anchored across the bottom with offsets rather than an explicit size, so
	# it re-centres at any window width.
	_subtitle.set_anchors_preset(Control.PRESET_BOTTOM_WIDE, true)
	_subtitle.offset_left = 24
	_subtitle.offset_right = -24
	_subtitle.offset_top = -152
	_subtitle.offset_bottom = -92
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.modulate.a = 0.0
	root.add_child(_subtitle)

	# --- Interaction prompt, centred just under the crosshair ---
	_prompt = UIKit.label("", UIKit.FONT_S, UIKit.GREEN)
	_prompt.set_anchors_preset(Control.PRESET_CENTER)
	_prompt.position = Vector2(-230, 40)
	_prompt.size = Vector2(460, 28)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_prompt)

	_crosshair = Control.new()
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	root.add_child(_crosshair)
	for conf: Array in [[Vector2(-11, -1), Vector2(8, 2)], [Vector2(4, -1), Vector2(8, 2)],
			[Vector2(-1, -11), Vector2(2, 8)], [Vector2(-1, 4), Vector2(2, 8)]]:
		var tick := ColorRect.new()
		tick.color = Color(0.75, 0.95, 0.78, 0.55)
		tick.position = conf[0]
		tick.size = conf[1]
		_crosshair.add_child(tick)


func _process(delta: float) -> void:
	if _subtitle_timer > 0.0:
		_subtitle_timer -= delta
		_subtitle.modulate.a = clampf(_subtitle_timer, 0.0, 1.0)
	var expired := false
	for n in _notices:
		n["life"] = float(n["life"]) - delta
		var lbl: Label = n["label"]
		if is_instance_valid(lbl):
			lbl.modulate.a = clampf(float(n["life"]) / 1.5, 0.0, 1.0)
		if float(n["life"]) <= 0.0:
			expired = true
	if expired:
		_prune_notices()
	if _player != null and is_instance_valid(_player):
		_refresh_player_bits()


func _refresh_player_bits() -> void:
	_replace_meter(_health_box, _health_bar, _player.health, _player.max_health, UIKit.RED)
	var bits: Array[String] = []
	if _player.holding_scanner:
		bits.append("scanner")
	if not _player.held_item.is_empty():
		bits.append(str(GameState.ITEMS[_player.held_item]["name"]).to_lower())
	if _player.held_illicit > 0:
		bits.append("%d under the counter" % _player.held_illicit)
	if not _player.equipped.is_empty():
		var w: Dictionary = GameState.WEAPONS[_player.equipped]
		bits.append("%s %s" % [str(w["name"]).to_lower(),
			"" if bool(w["melee"]) else "(%d)" % GameState.ammo_for(_player.equipped)])
	_hands.text = " · ".join(bits)


func _refresh_stats() -> void:
	_night_label.text = "NIGHT %d" % GameState.night
	_money_label.text = "%d" % GameState.money
	var earned := GameState.takings + GameState.illicit_takings + GameState.tips
	_quota_label.text = "rent %d   ·   tonight %d" % [GameState.rent_due(), earned]
	_quota_label.add_theme_color_override("font_color",
		UIKit.GREEN if earned >= GameState.rent_due() else UIKit.GREEN_DIM)
	_replace_meter(_heat_box, _heat_bar, GameState.heat, 100.0, UIKit.AMBER)


## Meters are plain ColorRects, so changing one means rebuilding it.
func _replace_meter(box: HBoxContainer, old: Control, value: float, maximum: float, colour: Color) -> void:
	if old == null or not is_instance_valid(old):
		return
	var idx := old.get_index()
	var fresh := UIKit.meter(value, maximum, METER_W, colour)
	box.remove_child(old)
	old.queue_free()
	box.add_child(fresh)
	box.move_child(fresh, idx)
	if box == _heat_box:
		_heat_bar = fresh
	else:
		_health_bar = fresh


func _on_prompt(text: String) -> void:
	_prompt.text = text


func _on_clock(minutes_left: float) -> void:
	# The shift runs 23:00 to 05:00, compressed. Showing it as a wall clock
	# rather than a countdown keeps it in the fiction.
	var total := 360.0
	var elapsed: float = clampf(total - minutes_left, 0.0, total)
	var h := int(23 + int(elapsed) / 60) % 24
	var m := int(elapsed) % 60
	_clock_label.text = "%02d:%02d" % [h, m]
	if minutes_left < 45.0:
		_clock_label.add_theme_color_override("font_color", UIKit.AMBER)


func _on_spoke(speaker: String, line: String) -> void:
	if not Settings.subtitles:
		return
	_subtitle.text = "%s:  \"%s\"" % [speaker.split(" ")[0], line]
	_subtitle_timer = 4.5
	_subtitle.modulate.a = 1.0


func _on_notice(text: String, tone: String) -> void:
	var lbl := UIKit.label("› " + text, UIKit.FONT_S, UIKit.tone_colour(tone))
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(520, 0)
	_notice_col.add_child(lbl)
	_notices.append({"label": lbl, "life": NOTICE_LIFETIME})
	while _notices.size() > MAX_NOTICES:
		var oldest: Dictionary = _notices.pop_front()
		var l: Label = oldest["label"]
		if is_instance_valid(l):
			l.queue_free()


func _prune_notices() -> void:
	var kept: Array[Dictionary] = []
	for n in _notices:
		if float(n["life"]) > 0.0:
			kept.append(n)
		else:
			var l: Label = n["label"]
			if is_instance_valid(l):
				l.queue_free()
	_notices = kept


func set_crosshair_visible(v: bool) -> void:
	_crosshair.visible = v
	_prompt.visible = v
