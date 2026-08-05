extends Node
## Global event bus.
##
## Systems talk through here rather than holding references to each other, so
## the night director, the UI and the world can be built and torn down
## independently between nights.

# --- Shift flow ---
signal night_started(night: int)
signal night_ended(summary: Dictionary)
signal quota_changed(current: int, target: int)
signal shift_clock(minutes_left: float)

# --- Customers ---
signal customer_arrived(customer: Node)
signal customer_departed(customer: Node, outcome: String)
signal customer_spoke(speaker: String, line: String)

# --- Player-facing state ---
signal money_changed(amount: int)
signal heat_changed(amount: float)
signal reputation_changed(amount: float)
signal notice(text: String, tone: String)

# --- Devices ---
signal scan_completed(findings: Array)
signal terminal_lookup(profile: Resource)
signal evidence_logged(entry: Dictionary)

# --- Danger ---
## Emitted by a customer as they hit the floor. Game.gd owns the body from
## there — the customer that raised it is about to free itself.
signal body_dropped(body: Node3D)

signal raid_incoming(reason: String)
signal flashbang()
signal raid_resolved(survived: bool)
signal player_died(cause: String)

# --- Interaction prompts ---
signal prompt_changed(text: String)

# --- Getting about ---
signal travel_requested(destination: Vector3, label: String, is_escape: bool)
signal easter_egg_found(path: String)
signal checkout_changed(scanned: int, total_items: int, price: int)
