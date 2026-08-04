class_name Checkout
extends Node
## Scanning, bagging and taking the money.
##
## The customer walks in, takes what they want off the shelves themselves and
## puts it down on the counter. From there it is your job: point at each item
## and press E to scan it — the beep, the price on the display, the thing going
## into the bag — and then hit the till.
##
## The till refuses while anything is still unscanned. That is the whole
## mechanic: a shop where you can just press "sell" is a menu, and the reason
## this one is worth doing is that you have to keep your eye on the counter
## while you are also deciding whether the person across it is police.

signal changed
signal completed(total: int)

var active: bool = false
var customer: Customer = null

var _world: World
var _items: Array[Dictionary] = []   ## {id, price, scanned, node}
var _total: int = 0
var _bagged: int = 0


func setup(world: World) -> void:
	_world = world


## Puts the customer's shopping on the counter. Returns the number of items;
## zero means the shelves were empty and there is nothing to sell them.
func begin(c: Customer, item_ids: Array[String]) -> int:
	clear()
	customer = c
	if item_ids.is_empty():
		return 0

	var slots: Array = _world.anchors.get("checkout_slots", [])
	if slots.is_empty():
		return 0

	for i in mini(item_ids.size(), slots.size()):
		var id: String = item_ids[i]
		var pos: Vector3 = slots[i]
		var tint: Color = World.SHELF_TINTS.get(id, Color(0.6, 0.6, 0.6))
		var body := _world.interact_zone(_world, "goods", pos, Vector3(0.30, 0.30, 0.30))
		body.set_meta("index", i)
		var box := ProcMesh.box(Vector3(0.18, 0.24, 0.18), Vector3.ZERO,
			ProcMesh.mat(ProcTex.product(tint, hash(id))), "Goods")
		box.rotation_degrees = Vector3(0, randf_range(-18, 18), 0)
		body.add_child(box)
		_items.append({
			"id": id,
			"price": int(GameState.ITEMS[id]["price"]),
			"scanned": false,
			"node": body,
		})

	active = true
	_total = 0
	_bagged = 0
	changed.emit()
	return _items.size()


## Scans one item: price on the total, item into the bag.
func scan(index: int) -> bool:
	if not active or index < 0 or index >= _items.size():
		return false
	var item: Dictionary = _items[index]
	if bool(item["scanned"]):
		Audio.play("deny", -18.0)
		Signals.notice.emit("Already scanned.", "warn")
		return false

	item["scanned"] = true
	_total += int(item["price"])
	_bagged += 1
	Audio.play("beep", -12.0)

	# Into the bag: the item slides across the counter and drops out of sight.
	var node: Node3D = item["node"]
	if is_instance_valid(node):
		var bag: Vector3 = _world.anchors.get("bag_spot", node.global_position)
		var tw := create_tween()
		tw.tween_property(node, "global_position", bag + Vector3(0, 0.18, 0), 0.22)
		tw.tween_property(node, "global_position", bag + Vector3(0, -0.10, 0), 0.18)
		tw.tween_callback(func() -> void:
			if is_instance_valid(node):
				node.visible = false)

	Signals.notice.emit("%s — %d" % [GameState.ITEMS[item["id"]]["name"], item["price"]], "info")
	changed.emit()
	return true


func remaining() -> int:
	var n := 0
	for item in _items:
		if not bool(item["scanned"]):
			n += 1
	return n


func all_scanned() -> bool:
	return active and remaining() == 0


func item_count() -> int:
	return _items.size()


func scanned_count() -> int:
	return _items.size() - remaining()


func total() -> int:
	return _total


## The till. Refuses while anything is unscanned — handing over goods you never
## rang up is how the takings quietly disappear.
func take_payment() -> bool:
	if not active:
		return false
	if not all_scanned():
		Audio.play("deny", -12.0)
		Signals.notice.emit("%d still to scan." % remaining(), "warn")
		return false

	var paid := _total
	GameState.add_money(paid, "takings")
	GameState.customers_served += 1
	Audio.play("register", -10.0)
	completed.emit(paid)
	clear()
	return true


func clear() -> void:
	for item in _items:
		var node: Node = item["node"]
		if is_instance_valid(node):
			node.queue_free()
	_items.clear()
	active = false
	customer = null
	_total = 0
	_bagged = 0
	changed.emit()


func item_name(index: int) -> String:
	if index < 0 or index >= _items.size():
		return ""
	return str(GameState.ITEMS[_items[index]["id"]]["name"])


func is_scanned(index: int) -> bool:
	if index < 0 or index >= _items.size():
		return false
	return bool(_items[index]["scanned"])
