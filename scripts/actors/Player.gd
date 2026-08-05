class_name Player
extends CharacterBody3D
## First-person controller for the person behind the counter.
##
## Movement is deliberately cramped. The interior is 4.5 m across, so this is
## less a walking simulator than a reaching simulator: most of what you do is
## turn on the spot and put your hands on things.

signal wants_terminal
signal wants_shop
signal wants_notebook
signal interacted_with_customer

const SPEED := 2.6
## Walking pace, and no faster, while carrying somebody.
const CARRY_SPEED := 1.5
const SPRINT := 4.0
const CROUCH_SPEED := 1.4
const ACCEL := 14.0
const MOUSE_SENS := 0.0022
const STAND_HEIGHT := 1.62
const CROUCH_HEIGHT := 0.95
const REACH := 2.4

var camera: Camera3D
var health: float = 100.0
var max_health: float = 100.0
var dead: bool = false

## Set while a full-screen panel is open. Movement and looking stop, but the
## world keeps running, so a customer can still walk out on you mid-lookup.
var ui_locked: bool = false

var holding_scanner: bool = false
var held_item: String = ""            ## Shelf item currently in hand.
var held_illicit: int = 0             ## Units from the stash currently in hand.
var equipped: String = ""             ## Weapon id, "" when hands are free.
## A bagged body over the shoulder. It fills both hands and slows you to a walk,
## which is the whole cost of having shot somebody: you cannot serve, you cannot
## shoot, and you are very obviously carrying a person.
var carried_body: Node3D = null
var _fire_cooldown: float = 0.0
var _bob: float = 0.0
var _target_height: float = STAND_HEIGHT
var _look_target: Node = null
var _view_root: Node3D
var _view_item: Node3D
var _muzzle_flash: OmniLight3D
var _torch: SpotLight3D
var torch_on: bool = false

var _ray: RayCast3D
var world: World
var checkout: Checkout


func _ready() -> void:
	name = "Player"
	# The easter egg and its reveal light both look for this group.
	add_to_group("player")
	collision_layer = 1
	collision_mask = 1
	var caps := CapsuleShape3D.new()
	caps.radius = 0.30
	caps.height = 1.75
	var cs := CollisionShape3D.new()
	cs.shape = caps
	cs.position = Vector3(0, 0.875, 0)
	add_child(cs)

	camera = Camera3D.new()
	camera.position = Vector3(0, STAND_HEIGHT, 0)
	camera.fov = 68.0
	camera.near = 0.05
	camera.far = 60.0
	add_child(camera)

	# Interaction ray only sees layer 2, so walls never steal a prompt.
	_ray = RayCast3D.new()
	_ray.target_position = Vector3(0, 0, -REACH)
	_ray.collision_mask = 0
	_ray.set_collision_mask_value(2, true)
	_ray.set_collision_mask_value(3, true)   # customers
	_ray.collide_with_areas = false
	camera.add_child(_ray)

	_view_root = Node3D.new()
	_view_root.position = Vector3(0.22, -0.20, -0.42)
	camera.add_child(_view_root)

	_muzzle_flash = OmniLight3D.new()
	_muzzle_flash.light_color = Color(1.0, 0.85, 0.55)
	_muzzle_flash.light_energy = 0.0
	_muzzle_flash.omni_range = 6.0
	camera.add_child(_muzzle_flash)

	# The kiosk is the only lit room in the game. Once you can walk out of it,
	# down a street with three working lamps and into a sewer, you need to be
	# able to carry light with you or the whole map is unplayable.
	_torch = SpotLight3D.new()
	_torch.position = Vector3(0.16, -0.12, 0.0)
	_torch.light_color = Color(1.0, 0.95, 0.84)
	_torch.light_energy = 0.0
	_torch.spot_range = 22.0
	_torch.spot_angle = 34.0
	_torch.spot_attenuation = 1.2
	camera.add_child(_torch)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if dead:
		return
	if event is InputEventMouseMotion and not ui_locked and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		var sens := MOUSE_SENS * Settings.mouse_sensitivity
		rotate_y(-mm.relative.x * sens)
		camera.rotate_x(-mm.relative.y * sens)
		camera.rotation.x = clampf(camera.rotation.x, -1.35, 1.35)


func _physics_process(delta: float) -> void:
	if dead:
		return
	_fire_cooldown = maxf(0.0, _fire_cooldown - delta)
	_muzzle_flash.light_energy = maxf(0.0, _muzzle_flash.light_energy - delta * 34.0)

	if ui_locked:
		velocity = velocity.move_toward(Vector3.ZERO, ACCEL * delta)
		move_and_slide()
		_update_prompt()
		return

	_move(delta)
	_update_prompt()
	_handle_actions()


func _move(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = 4.2

	var crouching := Input.is_action_pressed("crouch")
	_target_height = CROUCH_HEIGHT if crouching else STAND_HEIGHT

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	var speed := SPEED
	if crouching:
		speed = CROUCH_SPEED
	elif Input.is_action_pressed("sprint"):
		speed = SPRINT
	# Nobody sprints with a body on their shoulder.
	if carried_body != null and is_instance_valid(carried_body):
		speed = minf(speed, CARRY_SPEED)

	var target := dir * speed
	velocity.x = move_toward(velocity.x, target.x, ACCEL * delta)
	velocity.z = move_toward(velocity.z, target.z, ACCEL * delta)
	move_and_slide()

	# Head bob, and a footstep on each stride.
	var planar := Vector2(velocity.x, velocity.z).length()
	if planar > 0.4 and is_on_floor():
		var prev := _bob
		_bob += delta * planar * 2.1
		if int(prev / PI) != int(_bob / PI):
			Audio.play("footstep", -26.0, randf_range(0.85, 1.15))
	else:
		_bob = lerpf(_bob, 0.0, delta * 6.0)

	var bob_y := sin(_bob) * 0.022
	var bob_x := cos(_bob * 0.5) * 0.014
	camera.position.y = lerpf(camera.position.y, _target_height + bob_y, delta * 12.0)
	camera.position.x = lerpf(camera.position.x, bob_x, delta * 12.0)


# --- Interaction -------------------------------------------------------------

func _update_prompt() -> void:
	_look_target = null
	var text := ""
	if _ray.is_colliding():
		var hit := _ray.get_collider()
		if hit != null:
			_look_target = hit
			text = _prompt_for(hit)
	if carried_body != null and is_instance_valid(carried_body) and text.is_empty():
		text = "Carrying a body. The manhole is in the stockroom."
	elif not held_item.is_empty() and text.is_empty():
		text = "Carrying: %s" % GameState.ITEMS[held_item]["name"]
	Signals.prompt_changed.emit(text)


func _prompt_for(hit: Object) -> String:
	if hit.has_method("interaction_prompt"):
		return str(hit.call("interaction_prompt"))
	if not hit.has_meta("interact"):
		return ""
	var id := str(hit.get_meta("interact"))
	if id.begins_with("shelf:"):
		var item := id.substr(6)
		var units := GameState.shelf_units(item)
		if units <= 0:
			return "%s — empty  [Q] restock" % GameState.ITEMS[item]["name"]
		return "[E] Take %s  (%d left)   [Q] restock" % [GameState.ITEMS[item]["name"], units]
	match id:
		"till": return "[E] Till — %d" % GameState.money
		"terminal": return "[E] Terminal"
		"stash": return "[E] Under the counter  (%d)" % GameState.drug_stock
		"scanner": return "[E] Put the scanner down" if holding_scanner else "[E] Pick up the scanner"
		"crates": return "[E] Back stock"
		"shop": return "[E] Call the supplier"
		"shutter_control": return "[E] Shutter"
		"cash": return "[E] Pick up cash"
		"body":
			var b: Node = hit.get_meta("body_ref", null)
			return str(b.call("prompt")) if b != null and is_instance_valid(b) else ""
	return ""


func _handle_actions() -> void:
	if Input.is_action_just_pressed("notebook"):
		wants_notebook.emit()
		return
	if Input.is_action_just_pressed("holster"):
		_cycle_weapon()
	if Input.is_action_just_pressed("reload"):
		_reload()
	if Input.is_action_pressed("fire") and not equipped.is_empty():
		_fire()
	if Input.is_action_just_pressed("torch"):
		toggle_torch()
	if Input.is_action_just_pressed("scanner") and holding_scanner:
		_use_scanner()
	if Input.is_action_just_pressed("restock"):
		_restock_looked_at()
	if Input.is_action_just_pressed("interact"):
		_interact()


func _interact() -> void:
	if _look_target == null:
		return
	var hit := _look_target

	if hit.has_method("on_interact"):
		hit.call("on_interact", self)
		interacted_with_customer.emit()
		return

	if not hit.has_meta("interact"):
		return
	var id := str(hit.get_meta("interact"))

	if id.begins_with("shelf:"):
		var item := id.substr(6)
		if GameState.take_from_shelf(item):
			held_item = item
			held_illicit = 0
			_show_in_hand(item)
			Audio.play("click", -16.0)
			if world != null:
				world.refresh_shelves()
		else:
			Audio.play("deny", -14.0)
			Signals.notice.emit("Empty. There's more in the back.", "warn")
		return

	match id:
		"terminal":
			wants_terminal.emit()
		"shop":
			wants_shop.emit()
		"scanner":
			holding_scanner = not holding_scanner
			Audio.play("beep", -16.0)
			Signals.notice.emit("Scanner in hand. [F] to sweep." if holding_scanner else "Scanner down.", "info")
		"stash":
			if GameState.drug_stock <= 0:
				Audio.play("deny", -14.0)
				Signals.notice.emit("Nothing left under there.", "warn")
			else:
				GameState.drug_stock -= 1
				held_illicit += 1
				held_item = ""
				_show_in_hand("stash")
				Audio.play("click", -18.0)
				Signals.notice.emit("In your hand, out of sight.", "info")
		"goods":
			if checkout != null:
				checkout.scan(int(hit.get_meta("index", -1)))
		"till":
			if checkout != null and checkout.active:
				checkout.take_payment()
			else:
				Audio.play("register", -12.0)
				Signals.notice.emit("Takings tonight: %d. Rent: %d." %
					[GameState.takings + GameState.illicit_takings, GameState.rent_due()], "info")
		"crates":
			_restock_all()
		"shutter_control":
			if world != null:
				var closed: bool = bool(world.anchors.get("shutter_is_closed", false))
				world.anchors["shutter_is_closed"] = not closed
				world.set_shutter_closed(not closed)
				Audio.play("beep_low", -12.0)
				Signals.notice.emit("Shutter down. Nobody's buying anything now." if not closed else "Shutter up.", "info")
		"manhole", "manhole_street", "manhole_mid", \
		"ladder_up_stock", "ladder_up_street", "ladder_up_mid":
			# With somebody over your shoulder the manhole is a place to put them
			# down, not a place to climb into.
			if id == "manhole" and carried_body != null and is_instance_valid(carried_body):
				carried_body.call("dispose")
				carried_body = null
				return
			_travel(id)
		"sewer_cache":
			_open_cache(hit)
		"body":
			_handle_body(hit)
		"cash":
			var value := int(hit.get_meta("value", 5))
			GameState.add_money(value, "tips")
			Audio.play("register", -18.0)
			Signals.notice.emit("Found %d." % value, "good")
			(hit as Node).queue_free()


## Bagging one, then picking it up. Two presses, because they are two different
## decisions: a bag is a thing you have to have bought, and putting them over
## your shoulder is a thing you have to have time for.
func _handle_body(hit: Node) -> void:
	var b: Node = hit.get_meta("body_ref", null)
	if b == null or not is_instance_valid(b):
		return
	if carried_body != null and is_instance_valid(carried_body):
		Signals.notice.emit("You've already got one.", "warn")
		return
	if not bool(b.get("bagged")):
		if GameState.body_bags <= 0:
			Audio.play("deny", -14.0)
			Signals.notice.emit("No bags. The supplier sells them, and you should have thought of that.", "bad")
			return
		b.call("bag")
		return
	if bool(b.call("take_up")):
		carried_body = b
		# Both hands. You are not serving anybody or shooting anybody like this.
		clear_hands()
		equipped = ""
		holding_scanner = false
		Signals.notice.emit("Over your shoulder. Get to the manhole.", "warn")


## Somebody's crate at the end of the spur. There is one, it is worth about a
## night's rent, and once it is open it stays open for the rest of the run.
func _open_cache(hit: Node) -> void:
	var amount := GameState.open_sewer_cache()
	if amount <= 0:
		Signals.notice.emit("Empty. You already had this.", "info")
		return
	Audio.play("register", -14.0)
	Signals.notice.emit("Somebody's stash, under a board. %d." % amount, "good")
	Achievements.unlock("TUNNEL_RAT")
	if hit is Node3D:
		(hit as Node3D).queue_free()


## Ladders move you rather than being climbed. Climbing is a physics problem
## with no gameplay in it, and a hatch you press E on is unambiguous in a way a
## ladder collider never is. Game.gd does the fade and the actual move.
func _travel(which: String) -> void:
	if world == null:
		return
	var destination := Vector3.ZERO
	var label := ""
	match which:
		"manhole":
			destination = world.anchors.get("sewer_shaft_bottom", Vector3.ZERO)
			label = "Down into the dark."
		"manhole_street":
			destination = world.anchors.get("sewer_exit_bottom", Vector3.ZERO)
			label = "Down into the dark."
		"manhole_mid":
			destination = world.anchors.get("sewer_mid_bottom", Vector3.ZERO)
			label = "Down into the dark."
		"ladder_up_stock":
			destination = world.anchors.get("manhole", Vector3.ZERO) + Vector3(0, 0.2, -0.9)
			label = "Back up into the stockroom."
		"ladder_up_street":
			destination = world.anchors.get("sewer_exit_top", Vector3.ZERO) + Vector3(0, 0.2, -1.0)
			label = "Out into the alley."
		"ladder_up_mid":
			destination = world.anchors.get("sewer_mid_top", Vector3.ZERO) + Vector3(0, 0.2, -1.0)
			label = "Out onto the pavement, in full view."
	if destination == Vector3.ZERO:
		return
	# Going down from inside the kiosk is the escape route during a raid.
	var is_escape := which == "manhole"
	if destination.y < World.SEWER_Y + 2.0:
		Tutor.fire("torch")
		Tutor.fire("sewer")
	Audio.play("click", -14.0)
	Signals.travel_requested.emit(destination, label, is_escape)


func _restock_looked_at() -> void:
	if _look_target == null or not _look_target.has_meta("interact"):
		return
	var id := str(_look_target.get_meta("interact"))
	if not id.begins_with("shelf:"):
		return
	var item := id.substr(6)
	var moved := 0
	# Restock in a handful rather than one at a time; the tedium is not the
	# interesting part, the interruption is.
	for i in 4:
		if GameState.restock_one(item):
			moved += 1
	if moved > 0:
		Audio.play("click", -18.0)
		Signals.notice.emit("Filled %s (+%d)." % [GameState.ITEMS[item]["name"], moved], "good")
		if world != null:
			world.refresh_shelves()
	else:
		Audio.play("deny", -16.0)
		Signals.notice.emit("None left in the back. Call the supplier.", "warn")


func _restock_all() -> void:
	var moved := 0
	for item: String in GameState.ITEMS:
		while GameState.shelf_units(item) < 6 and GameState.restock_one(item):
			moved += 1
	if moved > 0:
		Audio.play("click", -14.0)
		Signals.notice.emit("Restocked the shelves (+%d)." % moved, "good")
		if world != null:
			world.refresh_shelves()
	else:
		Audio.play("deny", -16.0)
		Signals.notice.emit("Crates are empty.", "warn")


func clear_hands() -> void:
	held_item = ""
	held_illicit = 0
	_show_in_hand("")


# --- Scanner -----------------------------------------------------------------

func toggle_torch() -> void:
	torch_on = not torch_on
	_torch.light_energy = 5.5 if torch_on else 0.0
	Audio.play("click", -20.0)
	Signals.notice.emit("Torch on." if torch_on else "Torch off.", "info")


func _use_scanner() -> void:
	var target := _look_target
	if target == null or not target.has_method("on_scan"):
		Audio.play("deny", -16.0)
		Signals.notice.emit("Point it at someone.", "warn")
		return
	Audio.play("scanner", -10.0)
	target.call("on_scan", self)


# --- Weapons -----------------------------------------------------------------

func _cycle_weapon() -> void:
	var owned := GameState.weapons.duplicate()
	owned.push_front("")   # bare hands
	var idx := owned.find(equipped)
	equipped = owned[(idx + 1) % owned.size()]
	_show_in_hand("weapon" if not equipped.is_empty() else "")
	if equipped.is_empty():
		Signals.notice.emit("Hands free.", "info")
	else:
		var w: Dictionary = GameState.WEAPONS[equipped]
		Signals.notice.emit("%s  (%s)" % [w["name"], "—" if w["melee"] else str(GameState.ammo_for(equipped))], "info")
	Audio.play("click", -18.0)


func _reload() -> void:
	if equipped.is_empty():
		return
	Audio.play("click", -14.0)


func _fire() -> void:
	if _fire_cooldown > 0.0 or equipped.is_empty():
		return
	var w: Dictionary = GameState.WEAPONS[equipped]
	if not GameState.spend_ammo(equipped):
		Audio.play("deny", -12.0)
		_fire_cooldown = 0.4
		return

	_fire_cooldown = float(w["rate"])
	var melee := bool(w["melee"])
	Audio.play("swing" if melee else ("shotgun" if equipped == "shotgun" else "gunshot"), -4.0)
	if not melee:
		_muzzle_flash.light_energy = 3.2
		camera.rotation.x = clampf(camera.rotation.x + randf_range(0.02, 0.05), -1.35, 1.35)

	var pellets: int = int(w.get("pellets", 1))
	var spread := float(w["spread"])
	var range_m := 2.0 if melee else 30.0

	for i in pellets:
		var space := get_world_3d().direct_space_state
		var from := camera.global_position
		var dir := -camera.global_transform.basis.z
		if spread > 0.0:
			dir = (dir + Vector3(randf_range(-spread, spread), randf_range(-spread, spread), 0.0)).normalized()
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * range_m)
		q.collision_mask = 0
		q.exclude = [get_rid()]
		var mask := 0
		mask |= 1 << 0   # world
		mask |= 1 << 2   # characters
		q.collision_mask = mask
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var collider: Object = hit["collider"]
		if collider != null and collider.has_method("take_damage"):
			collider.call("take_damage", float(w["damage"]), self)
			Audio.play("impact", -14.0)


func take_damage(amount: float, _source: Object = null) -> void:
	if dead:
		return
	health -= amount
	Audio.play("impact", -8.0)
	if health <= 0.0:
		die("shot")


func die(cause: String) -> void:
	if dead:
		return
	dead = true
	health = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var tw := create_tween()
	tw.tween_property(camera, "position:y", 0.35, 0.9).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(camera, "rotation:z", deg_to_rad(62.0), 0.9)
	Signals.player_died.emit(cause)


# --- View model --------------------------------------------------------------

## A crude object in the bottom-right of the view so you can see what is in
## your hands without opening anything.
func _show_in_hand(kind: String) -> void:
	if _view_item != null and is_instance_valid(_view_item):
		_view_item.queue_free()
		_view_item = null
	if kind.is_empty():
		return

	var m: Material
	var size: Vector3
	match kind:
		"stash":
			m = ProcMesh.mat(ProcTex.flat(Color(0.72, 0.70, 0.66)))
			size = Vector3(0.055, 0.075, 0.012)
		"weapon":
			var w: Dictionary = GameState.WEAPONS.get(equipped, {})
			m = ProcMesh.mat(ProcTex.metal(Color(0.16, 0.16, 0.18), 3))
			size = Vector3(0.05, 0.09, 0.30) if not bool(w.get("melee", false)) else Vector3(0.05, 0.05, 0.55)
		_:
			var tint: Color = World.SHELF_TINTS.get(kind, Color(0.6, 0.6, 0.6))
			m = ProcMesh.mat(ProcTex.product(tint, hash(kind)))
			size = Vector3(0.075, 0.10, 0.075)

	_view_item = ProcMesh.box(size, Vector3.ZERO, m, "InHand")
	_view_item.rotation_degrees = Vector3(-8, 22, 6)
	# Draw on top of the world so it never clips through the counter.
	(_view_item as MeshInstance3D).sorting_offset = 4.0
	_view_root.add_child(_view_item)
