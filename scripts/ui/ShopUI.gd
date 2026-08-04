class_name ShopUI
extends CanvasLayer
## The supplier, reached on the phone screwed to the wall.
##
## Deliveries arrive "in the morning", which mechanically means immediately —
## the kiosk is the only place in the game, so an order screen is the only
## honest way to let you spend what you earned.

signal closed

var open: bool = false
var _root: Control
var _list: VBoxContainer
var _money_label: Label
var _tab: String = "stock"


func _ready() -> void:
	layer = 8
	visible = false


func show_shop() -> void:
	open = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Audio.play("beep", -14.0)
	_rebuild()


func close() -> void:
	open = false
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not open:
		return
	if event.is_action_pressed("cancel"):
		close()
		get_viewport().set_input_as_handled()


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()

	var m := UIKit.modal("SUPPLIER  ·  ORDER LINE", 0.88, 0.94)
	_root = m["root"]
	var body: VBoxContainer = m["body"]
	add_child(_root)

	_money_label = UIKit.label("On hand: %d" % GameState.money, UIKit.FONT_M, UIKit.GREEN)
	body.add_child(_money_label)
	body.add_child(UIKit.spacer(4))

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	for conf: Array in [["stock", "SHELF STOCK"], ["under", "UNDER THE COUNTER"],
			["arms", "ARMS"], ["fittings", "FITTINGS"]]:
		var b := Button.new()
		b.text = conf[1]
		b.add_theme_font_size_override("font_size", UIKit.FONT_S)
		b.add_theme_color_override("font_color", UIKit.GREEN if _tab == conf[0] else UIKit.GREEN_DIM)
		b.flat = true
		b.pressed.connect(func() -> void:
			_tab = conf[0]
			Audio.play("click", -20.0)
			_rebuild())
		tabs.add_child(b)
	body.add_child(tabs)
	body.add_child(UIKit.rule())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 180)
	body.add_child(scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 3)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	match _tab:
		"stock": _build_stock()
		"under": _build_under()
		"arms": _build_arms()
		"fittings": _build_fittings()

	body.add_child(UIKit.rule())
	body.add_child(UIKit.label("[ESC] hang up", UIKit.FONT_S, UIKit.GREEN_DIM))


func _row(title: String, subtitle: String, price: int, affordable: bool, on_buy: Callable, owned: String = "") -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	col.add_child(UIKit.label(title, UIKit.FONT_S, UIKit.WHITE))
	if not subtitle.is_empty():
		col.add_child(UIKit.label(subtitle, UIKit.FONT_S, UIKit.GREEN_DIM))
	row.add_child(col)

	if not owned.is_empty():
		row.add_child(UIKit.label(owned, UIKit.FONT_S, UIKit.GREEN_DIM))

	var b := Button.new()
	b.text = "%d" % price
	b.custom_minimum_size = Vector2(72, 0)
	b.disabled = not affordable
	b.add_theme_font_size_override("font_size", UIKit.FONT_S)
	b.add_theme_color_override("font_color", UIKit.GREEN if affordable else UIKit.GREEN_DIM)
	b.pressed.connect(func() -> void:
		if GameState.spend(price):
			on_buy.call()
			Audio.play("register", -14.0)
			_rebuild()
		else:
			Audio.play("deny", -14.0))
	row.add_child(b)
	_list.add_child(row)


func _build_stock() -> void:
	for id: String in GameState.ITEMS:
		var item: Dictionary = GameState.ITEMS[id]
		var cost: int = int(item["cost"]) * 6
		var margin: int = (int(item["price"]) - int(item["cost"])) * 6
		_row("%s  ×6" % item["name"], "sells for %d each · %d margin on the case" % [item["price"], margin],
			cost, GameState.money >= cost,
			func() -> void: GameState.crate_stock[id] = int(GameState.crate_stock.get(id, 0)) + 6,
			"back: %d  shelf: %d" % [int(GameState.crate_stock.get(id, 0)), GameState.shelf_units(id)])


func _build_under() -> void:
	_list.add_child(UIKit.label(
		"He doesn't say what it is on the phone and neither do you.",
		UIKit.FONT_S, UIKit.GREEN_DIM))
	_list.add_child(UIKit.spacer(4))
	for batch: int in [3, 6, 12]:
		# Bigger batches are cheaper per unit, which quietly pushes you into
		# holding more stock than you can safely move in one night.
		var discount := 1.0 - 0.06 * float([3, 6, 12].find(batch))
		var price := int(float(batch * GameState.illicit_unit_cost()) * discount)
		_row("%d units" % batch, "%d a unit · they go for %d–%d, depending who's asking" %
			[int(float(price) / float(batch)), 38 + GameState.night * 7, 66 + GameState.night * 7],
			price, GameState.money >= price,
			func() -> void: GameState.drug_stock += batch,
			"under the counter: %d" % GameState.drug_stock)


func _build_arms() -> void:
	for id: String in GameState.WEAPONS:
		var w: Dictionary = GameState.WEAPONS[id]
		var owned := GameState.has_weapon(id)
		if owned:
			_list.add_child(UIKit.label("%s — owned" % w["name"], UIKit.FONT_S, UIKit.GREEN_DIM))
		else:
			var price := int(w["price"])
			_row(str(w["name"]), "damage %d · %s" % [w["damage"], "melee" if w["melee"] else "firearm"],
				price, GameState.money >= price,
				func() -> void: GameState.weapons.append(id))
	_list.add_child(UIKit.spacer(6))
	_list.add_child(UIKit.rule())
	for id: String in GameState.AMMO_PRICE:
		if not GameState.has_weapon(id):
			continue
		var price: int = int(GameState.AMMO_PRICE[id])
		var per: int = int(GameState.AMMO_PER_BOX[id])
		_row("%s ammunition  ×%d" % [GameState.WEAPONS[id]["name"], per], "",
			price, GameState.money >= price,
			func() -> void: GameState.add_ammo(id, per),
			"have: %d" % GameState.ammo_for(id))


func _build_fittings() -> void:
	for id: String in GameState.DEFENSES:
		var d: Dictionary = GameState.DEFENSES[id]
		if GameState.defenses.has(id):
			_list.add_child(UIKit.label("%s — fitted" % d["name"], UIKit.FONT_S, UIKit.GREEN_DIM))
			continue
		var price := int(d["price"])
		_row(str(d["name"]), str(d["desc"]), price, GameState.money >= price,
			func() -> void: GameState.defenses.append(id))
	_list.add_child(UIKit.spacer(6))
	_row("Body bags  ×2", "for the nights it goes badly", 55, GameState.money >= 55,
		func() -> void: GameState.body_bags += 2,
		"have: %d" % GameState.body_bags)
