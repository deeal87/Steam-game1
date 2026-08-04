class_name NotebookUI
extends CanvasLayer
## The pad by the till.
##
## Everything in here is already knowable from the world — it exists so you can
## check what you have on the person at the window without walking back to the
## terminal and losing them.

signal closed

var open: bool = false
var _customer: Customer


func _ready() -> void:
	layer = 8
	visible = false


func show_notebook(customer: Customer) -> void:
	_customer = customer
	open = true
	visible = true
	_rebuild()
	Audio.play("click", -22.0)


func close() -> void:
	open = false
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not open:
		return
	if event.is_action_pressed("cancel") or event.is_action_pressed("notebook"):
		close()
		get_viewport().set_input_as_handled()


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()

	var m := UIKit.modal("NOTEPAD", 0.80, 0.90)
	var body: VBoxContainer = m["body"]
	add_child(m["root"])

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 20)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(cols)

	# --- Left: the person at the window ---
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 3)
	cols.add_child(left)

	if _customer == null or not is_instance_valid(_customer) or _customer.profile == null:
		left.add_child(UIKit.label("Nobody at the window.", UIKit.FONT_S, UIKit.GREEN_DIM))
	else:
		var p := _customer.profile
		left.add_child(UIKit.label(p.full_name if p.looked_up else "Unidentified", UIKit.FONT_M, UIKit.WHITE))
		left.add_child(UIKit.label(p.read_out(), UIKit.FONT_S, UIKit.AMBER))
		left.add_child(UIKit.spacer(4))
		left.add_child(UIKit.field("Swept", "yes" if p.scanned else "no"))
		left.add_child(UIKit.field("File pulled", "yes" if p.looked_up else "no"))
		left.add_child(UIKit.field("Patience", "%d of %d" % [p.patience, p.patience_max]))
		left.add_child(UIKit.field("Asking for", "the other thing" if p.wants_illicit else "shelf goods only"))
		left.add_child(UIKit.spacer(6))
		var evidence := p.evidence_lines()
		if evidence.is_empty():
			left.add_child(UIKit.label("Nothing written down yet.", UIKit.FONT_S, UIKit.GREEN_DIM))
		else:
			for line in evidence:
				var l := UIKit.label(line, UIKit.FONT_S, UIKit.WHITE)
				l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				left.add_child(l)

	# --- Right: the night, and how the controls work ---
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 3)
	cols.add_child(right)

	right.add_child(UIKit.label("TONIGHT", UIKit.FONT_S, UIKit.GREEN_DIM))
	right.add_child(UIKit.field("Served", str(GameState.customers_served)))
	right.add_child(UIKit.field("Over the counter", str(GameState.takings)))
	right.add_child(UIKit.field("Under it", str(GameState.illicit_takings)))
	right.add_child(UIKit.field("Tips and finds", str(GameState.tips)))
	right.add_child(UIKit.field("Rent due", str(GameState.rent_due()),
		UIKit.GREEN if GameState.takings + GameState.illicit_takings + GameState.tips >= GameState.rent_due() else UIKit.RED))
	right.add_child(UIKit.field("Under the counter", "%d units" % GameState.drug_stock))
	right.add_child(UIKit.field("Body bags", str(GameState.body_bags)))
	if GameState.evidence_against_you > 0:
		right.add_child(UIKit.spacer(4))
		right.add_child(UIKit.label("Someone walked away tonight who shouldn't have.", UIKit.FONT_S, UIKit.RED))

	right.add_child(UIKit.spacer(8))
	right.add_child(UIKit.label("HOW ANY OF THIS WORKS", UIKit.FONT_S, UIKit.GREEN_DIM))
	for line: String in [
		"E — use, take, hand over",
		"Q — refill the shelf you're looking at",
		"F — sweep them with the scanner",
		"TAB — this pad",
		"X — change what's in your hands",
		"MOUSE 1 — use it",
	]:
		right.add_child(UIKit.label(line, UIKit.FONT_S, UIKit.WHITE))

	body.add_child(UIKit.spacer(6))
	body.add_child(UIKit.rule())
	body.add_child(UIKit.label("[TAB] or [ESC] put it down", UIKit.FONT_S, UIKit.GREEN_DIM))
