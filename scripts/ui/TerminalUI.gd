class_name TerminalUI
extends CanvasLayer
## The computer on the counter.
##
## Diegetically this is a municipal registry terminal with an analysis package
## bolted on, and the package is the reason the kiosk can do the business it
## does: point it at whoever is at the hatch and it pulls their file and tells
## you what it thinks.
##
## What it will not do is tell you they are a police officer. It reports what
## the record says and where the record contradicts itself. Reading those
## contradictions is your job — the machine only ever hands you the questions.

signal closed

const TYPE_SPEED := 220.0   ## characters per second

var open: bool = false
var _root: Control
var _body: VBoxContainer
var _assessment: RichTextLabel
var _assessment_full: String = ""
var _typed: float = 0.0
var _subject: Customer


func _ready() -> void:
	layer = 8
	visible = false


func show_for(customer: Customer) -> void:
	_subject = customer
	open = true
	visible = true
	if customer != null:
		customer.on_lookup()
	_rebuild()
	Audio.play("beep", -14.0)


func close() -> void:
	open = false
	visible = false
	_subject = null
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not open:
		return
	if event.is_action_pressed("cancel") or event.is_action_pressed("interact"):
		close()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not open or _assessment == null:
		return
	if _typed < float(_assessment_full.length()):
		var before := int(_typed)
		_typed += TYPE_SPEED * delta
		_assessment.visible_characters = int(_typed)
		if int(_typed) / 6 != before / 6:
			Audio.play("typing", -34.0)


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()

	var m := UIKit.modal("IDENT-7  ·  CIVIL REGISTRY  ·  TERMINAL 04", 0.86, 0.92)
	_root = m["root"]
	_body = m["body"]
	add_child(_root)

	if _subject == null or _subject.profile == null:
		_body.add_child(UIKit.label("NO SUBJECT AT THE WINDOW.", UIKit.FONT_M, UIKit.GREEN_DIM))
		_body.add_child(UIKit.label("\nStand at the hatch with someone in front of you and try again.",
			UIKit.FONT_S, UIKit.GREEN_DIM))
		_footer()
		return

	var p := _subject.profile
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(columns)

	columns.add_child(_photo_column(p))

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 3)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)

	right.add_child(UIKit.field("NAME", p.full_name, UIKit.WHITE))
	right.add_child(UIKit.field("DATE OF BIRTH", "%s  (age %d)" % [p.dob, p.age]))
	right.add_child(UIKit.field("IDENTITY NO.", p.id_number))
	right.add_child(UIKit.field("ISSUED", p.id_issued, _flag_colour(p, "id_recent")))
	right.add_child(UIKit.field("EXPIRES", p.id_expires))
	right.add_child(UIKit.spacer(4))
	right.add_child(UIKit.field("ADDRESS", p.address_line(), _flag_colour(p, "address_precinct")))
	right.add_child(UIKit.field("OCCUPATION", p.occupation))
	right.add_child(UIKit.field("EMPLOYER", p.employer, _flag_colour(p, "employer_front")))
	right.add_child(UIKit.field("VEHICLE", p.vehicle_desc, _flag_colour(p, "vehicle_fleet")))
	right.add_child(UIKit.spacer(4))
	right.add_child(UIKit.field("TELEPHONE", "%s  (registered %s)" % [p.phone, p.phone_registered],
		_flag_colour(p, "phone_new")))
	right.add_child(UIKit.field("UTILITIES", p.utilities, _flag_colour(p, "no_utilities")))
	right.add_child(UIKit.field("EMPLOYMENT", p.employment_note, _flag_colour(p, "employment_gap")))
	right.add_child(UIKit.field("NEXT OF KIN", p.next_of_kin, _flag_colour(p, "kin_switchboard")))
	right.add_child(UIKit.spacer(4))

	var record_text := "None on file."
	if not p.record.is_empty():
		record_text = "\n".join(p.record)
	right.add_child(UIKit.field("PRIOR MATTERS", record_text, _flag_colour(p, "record_scrubbed")))

	_body.add_child(UIKit.spacer(6))
	_body.add_child(UIKit.rule())
	_body.add_child(UIKit.label("ANALYSIS", UIKit.FONT_S, UIKit.GREEN_DIM))

	_assessment_full = _compose_assessment(p)
	_assessment = UIKit.rich(_assessment_full, UIKit.FONT_S, UIKit.GREEN)
	_assessment.custom_minimum_size = Vector2(0, 92)
	_assessment.visible_characters = 0
	_typed = 0.0
	_body.add_child(_assessment)

	_footer()


## Amber once the player has actually turned the anomaly up. Until then the
## field reads like any other, which is the whole reason you have to look.
func _flag_colour(p: CustomerProfile, tell_id: String) -> Color:
	if p.has_tell(tell_id) and p.tell_state(tell_id).get("discovered", false):
		return UIKit.AMBER
	return UIKit.WHITE


func _photo_column(p: CustomerProfile) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)

	var photo := TextureRect.new()
	photo.texture = ProcTex.face(p.seed_value, 32)
	photo.custom_minimum_size = Vector2(112, 112)
	photo.stretch_mode = TextureRect.STRETCH_SCALE
	photo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	col.add_child(photo)

	col.add_child(UIKit.label("REGISTRY PHOTOGRAPH", UIKit.FONT_S, UIKit.GREEN_DIM))
	var history := "Images on file: %d" % (1 if p.has_tell("file_thin") else randi_range(2, 5))
	col.add_child(UIKit.label(history, UIKit.FONT_S,
		UIKit.AMBER if p.has_tell("file_thin") and p.tell_state("file_thin").get("discovered", false) else UIKit.GREEN_DIM))
	return col


## Writes the terminal's report.
##
## It is assembled from facts the player has actually uncovered, phrased as an
## analyst would phrase them: flat, specific, and stopping short of the
## conclusion. Every sentence here is something you could have worked out from
## the fields above — the machine is a reading aid, not an oracle.
func _compose_assessment(p: CustomerProfile) -> String:
	var lines: Array[String] = []
	var found := p.discovered_tells(Tells.CHANNEL_TERMINAL)

	if found.is_empty():
		lines.append("Record is internally consistent. Employment, address and identity documents agree with one another and with the issuing authority.")
		if p.record.is_empty():
			lines.append("No prior matters. Not unusual for this age bracket.")
		lines.append("[color=#41854f]No documentary anomalies.[/color]")
	else:
		lines.append("[color=#f5c252]%d anomal%s in the record:[/color]" % [found.size(), "y" if found.size() == 1 else "ies"])
		for id: String in found:
			lines.append("  · " + str(Tells.get_tell(id)["label"]))
		lines.append("")
		lines.append("These may each have an ordinary explanation. Ask.")

	# It flags the shape of a fabricated file without ever naming what it is.
	if found.size() >= 3:
		lines.append("[color=#f55c57]Note: a file with this many discrepancies is more often a constructed identity than a badly kept one.[/color]")

	if p.scanned:
		var scan_found := p.discovered_tells(Tells.CHANNEL_SCANNER)
		lines.append("")
		if scan_found.is_empty():
			lines.append("Sweep returned nothing carried.")
		else:
			lines.append("Cross-reference with sweep: %d item%s on their person unaccounted for by the file." %
				[scan_found.size(), "" if scan_found.size() == 1 else "s"])

	return "\n".join(lines)


func _footer() -> void:
	_body.add_child(UIKit.spacer(8))
	_body.add_child(UIKit.rule())
	_body.add_child(UIKit.label("[E] or [ESC] step away from the terminal", UIKit.FONT_S, UIKit.GREEN_DIM))
