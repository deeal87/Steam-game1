class_name ProfileGenerator
extends RefCounted
## Builds the people who walk in.
##
## Two rules govern the whole thing.
##
## First: an officer's file is a fabrication the department built, so the seams
## are *in the file*. That is why the terminal is worth using at all.
##
## Second: every tell an officer can leak is one an innocent person can also
## have. The difference is only ever in whether they can explain it.

const FIRST_NAMES := [
	"Anders", "Mira", "Tomas", "Ilva", "Petr", "Rosa", "Danek", "Yara",
	"Kell", "Nadia", "Vasil", "Elsa", "Marek", "Juno", "Otto", "Sabine",
	"Lasse", "Vera", "Emil", "Katri", "Rune", "Hana", "Bo", "Ines",
	"Wim", "Greta", "Ivo", "Solvi", "Arne", "Tessa", "Lukas", "Mirek",
]

const SURNAMES := [
	"Vesely", "Halloran", "Brandt", "Novak", "Ferris", "Klimt", "Sorge",
	"Dressler", "Marek", "Ostrowski", "Vance", "Rehn", "Kaspar", "Lund",
	"Bittner", "Corvo", "Radek", "Falk", "Weiss", "Petrov", "Doyle",
	"Szabo", "Hain", "Mercer", "Kroll", "Vogel", "Stark", "Behr",
]

const DISTRICTS := [
	"Pikestone", "Old Dock", "Cauldwell", "Sallow Row", "Marlow Gate",
	"Brick Fields", "Kessler Hill", "Ninth District", "Vane",
]

const STREETS := [
	"Cutter Lane", "Alder Row", "Gassner Street", "Bell Yard", "Wick Road",
	"Tannery Walk", "Dunbar Street", "Sixteen Steps", "Corn Alley",
	"Prosper Street", "Kalb Passage", "Weaver Street",
]

## Officers get housed here. It is a real place with real civilian tenants,
## which is exactly why the address alone proves nothing.
const PRECINCT_STREET := "Roth Street"

const JOBS := [
	{"occupation": "Night porter", "employer": "Vane Street Depot"},
	{"occupation": "Taxi driver", "employer": "Kessler Cabs"},
	{"occupation": "Warehouse picker", "employer": "Halloran Logistics"},
	{"occupation": "Auxiliary nurse", "employer": "St. Brannoc's"},
	{"occupation": "Line cook", "employer": "The Blue Kettle"},
	{"occupation": "Security guard", "employer": "Merit Site Services"},
	{"occupation": "Cleaner", "employer": "Brightway Contracts"},
	{"occupation": "Bus driver", "employer": "City Transit"},
	{"occupation": "Mechanic", "employer": "Radek & Sons"},
	{"occupation": "Delivery rider", "employer": "Quickline"},
	{"occupation": "Welder", "employer": "Dock Fabrication"},
	{"occupation": "Barman", "employer": "The Hanged Man"},
	{"occupation": "Care worker", "employer": "Alder House"},
	{"occupation": "Roofer", "employer": "Bittner Roofing"},
	{"occupation": "Print operator", "employer": "Ninth District Press"},
	{"occupation": "Refuse loader", "employer": "City Sanitation"},
	{"occupation": "Unemployed", "employer": "—"},
	{"occupation": "Student", "employer": "Kessler Polytechnic"},
]

## Companies with no premises and no filings. An officer's cover employer.
const FRONT_EMPLOYERS := [
	"Meridian Facilities Group", "Northgate Asset Holdings",
	"Calder Site Management", "Ashford Contract Services",
	"Pinnacle Support Partners",
]

const CAR_MAKES := ["Vesper", "Kolt", "Brandt", "Marlin", "Ostrow", "Dace"]
const CAR_COLOURS := ["grey", "brown", "dark blue", "white", "green", "red", "black"]

const RECORD_POOL := [
	"Drunk and disorderly", "Driving without insurance", "Possession, minor",
	"Criminal damage", "Theft, retail", "Breach of the peace",
	"Failure to appear", "Assault, common", "Handling stolen goods",
	"Trespass", "Public urination", "Unpaid fines",
]

const GREETINGS := [
	"Evening.", "Still open, then.", "Cold one.", "Alright.",
	"Didn't think anywhere'd be open.", "Long night?", "You're the only light on.",
	"Rain's not letting up.", "Nothing else for a mile, is there?",
]

const ILLICIT_LINES := [
	"...and the other thing. If you've got it.",
	"Someone said you keep something under there.",
	"I'm not just here for crisps.",
	"You do the other business, don't you?",
	"Under the counter. That's the phrase, isn't it?",
]

## Words that fell out of use on this street a decade ago.
const STALE_SLANG_LINES := [
	"You holding any of the beige?",
	"Got any tickets going?",
	"Looking for a bit of the brown sugar.",
	"Any of the good gear? The proper gear?",
]

const MONTHS := ["January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December"]


static func _pick(arr: Array, rng: RandomNumberGenerator) -> Variant:
	return arr[rng.randi() % arr.size()]


static func _date(rng: RandomNumberGenerator, year_lo: int, year_hi: int) -> String:
	return "%d %s %d" % [
		rng.randi_range(1, 28),
		MONTHS[rng.randi() % 12],
		rng.randi_range(year_lo, year_hi),
	]


## `night` scales how careful the officers are. `undercover_chance` comes from
## GameState so heat feeds into it.
static func generate(seed_value: int, night: int, undercover_chance: float) -> CustomerProfile:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var p := CustomerProfile.new()
	p.seed_value = seed_value
	p.kind = CustomerProfile.Kind.UNDERCOVER if rng.randf() < undercover_chance else CustomerProfile.Kind.CIVILIAN

	# --- Identity ---
	p.full_name = "%s %s" % [_pick(FIRST_NAMES, rng), _pick(SURNAMES, rng)]
	p.age = rng.randi_range(19, 64)
	p.dob = _date(rng, 2026 - p.age - 1, 2026 - p.age)
	p.id_number = "%s-%04d-%03d" % [
		String.chr(65 + rng.randi() % 26) + String.chr(65 + rng.randi() % 26),
		rng.randi_range(1000, 9999),
		rng.randi_range(100, 999),
	]
	p.id_issued = _date(rng, 2021, 2025)
	p.id_expires = _date(rng, 2029, 2034)
	p.street = "%d %s" % [rng.randi_range(1, 180), _pick(STREETS, rng)]
	p.district = _pick(DISTRICTS, rng)

	var job: Dictionary = _pick(JOBS, rng)
	p.occupation = job["occupation"]
	p.employer = job["employer"]

	if rng.randf() < 0.45:
		p.plate = "%s%s %d%d%d" % [
			String.chr(65 + rng.randi() % 26), String.chr(65 + rng.randi() % 26),
			rng.randi() % 10, rng.randi() % 10, rng.randi() % 10,
		]
		p.vehicle_desc = "%s %s (%s)" % [_pick(CAR_COLOURS, rng), _pick(CAR_MAKES, rng), p.plate]
	else:
		p.vehicle_desc = "None registered"
		p.plate = "—"

	var n_record := rng.randi_range(0, 3)
	for i in n_record:
		var entry: String = "%s (%d)" % [_pick(RECORD_POOL, rng), rng.randi_range(2014, 2025)]
		if not p.record.has(entry):
			p.record.append(entry)

	p.height_scale = rng.randf_range(0.90, 1.10)
	p.bulk_scale = rng.randf_range(0.88, 1.18)
	p.greeting = _pick(GREETINGS, rng)

	# --- What they came in for ---
	var item_ids: Array = GameState.ITEMS.keys()
	var n_items := rng.randi_range(1, 3)
	for i in n_items:
		var id: String = item_ids[rng.randi() % item_ids.size()]
		if not p.order.has(id):
			p.order.append(id)

	# An officer is here to make a buy, so they always ask. Plenty of ordinary
	# people ask too — otherwise the question would answer itself.
	if p.kind == CustomerProfile.Kind.UNDERCOVER:
		p.wants_illicit = true
		p.illicit_units = rng.randi_range(1, 2)
	else:
		p.wants_illicit = rng.randf() < 0.35
		p.illicit_units = rng.randi_range(1, 2)

	_assign_tells(p, rng, night)
	_apply_tell_consequences(p, rng)
	_write_base_answers(p, rng, night)

	p.patience_max = rng.randi_range(4, 6)
	if p.kind == CustomerProfile.Kind.UNDERCOVER:
		# Officers hold their nerve slightly longer; walking out is a failed op.
		p.patience_max += 1
	p.patience = p.patience_max

	# Later nights send better-prepared officers, whose cover documents hold up
	# to more of your questions. This is the main reason the game gets harder:
	# not that there are more of them, but that asking stops being decisive.
	if p.kind == CustomerProfile.Kind.UNDERCOVER:
		p.cover_strength = clampf(0.16 + 0.038 * float(night - 1), 0.0, 0.52)
	else:
		p.cover_strength = 0.0
	# Roughly one innocent person in six will not explain themselves, whatever
	# you ask. They are the reason you can never convict on a single answer.
	p.nerves = rng.randf_range(0.10, 0.22)

	return p


static func _assign_tells(p: CustomerProfile, rng: RandomNumberGenerator, night: int) -> void:
	var pool := Tells.all_ids()
	pool.shuffle()

	var wanted: int
	if p.kind == CustomerProfile.Kind.UNDERCOVER:
		wanted = GameState.tells_for_undercover()
	else:
		wanted = GameState.false_tells_for_civilian()

	var chosen: Array[String] = []
	if p.kind == CustomerProfile.Kind.UNDERCOVER:
		# Guarantee at least one non-scanner tell, so a player who only ever
		# scans is never able to clear a night on the scanner alone.
		var non_scanner: Array[String] = []
		for id: String in pool:
			if Tells.get_tell(id)["channel"] != Tells.CHANNEL_SCANNER:
				non_scanner.append(id)
		if not non_scanner.is_empty():
			chosen.append(non_scanner[rng.randi() % non_scanner.size()])

	for id: String in pool:
		if chosen.size() >= wanted:
			break
		if not chosen.has(id):
			chosen.append(id)

	for id: String in chosen:
		p.tells[id] = {"discovered": false, "asked": false, "outcome": ""}


## Some tells have to be true of the file itself, not merely asserted. If the
## terminal says a tell is there, the record has to actually show it.
static func _apply_tell_consequences(p: CustomerProfile, rng: RandomNumberGenerator) -> void:
	if p.has_tell("employer_front"):
		p.employer = FRONT_EMPLOYERS[rng.randi() % FRONT_EMPLOYERS.size()]
	if p.has_tell("address_precinct"):
		p.street = "%d %s" % [rng.randi_range(1, 40), PRECINCT_STREET]
	if p.has_tell("record_scrubbed"):
		p.record.clear()
	if p.has_tell("id_recent"):
		p.id_issued = "%d %s 2026" % [rng.randi_range(1, 28), MONTHS[2]]
	if p.has_tell("vehicle_fleet"):
		p.plate = "CT %d%d%d" % [rng.randi() % 10, rng.randi() % 10, rng.randi() % 10]
		p.vehicle_desc = "white Kolt panel van (%s)" % p.plate
	if p.has_tell("wrong_slang"):
		p.wants_illicit = true


## Answers to the four standing questions.
##
## For a civilian these always match the file. For an officer they usually
## match too — the cover is rehearsed — but there is a chance per question that
## the story and the paperwork come apart. That chance shrinks as the nights go
## on, so the standing questions get less reliable exactly as everything else
## gets harder.
static func _write_base_answers(p: CustomerProfile, rng: RandomNumberGenerator, night: int) -> void:
	var slip_chance := 0.0
	if p.kind == CustomerProfile.Kind.UNDERCOVER:
		slip_chance = maxf(0.12, 0.42 - 0.045 * float(night - 1))

	for qid: String in Tells.BASE_QUESTIONS:
		var field: String = Tells.BASE_QUESTIONS[qid]["field"]
		var truth: String = str(p.get(field))
		var slipped: bool = rng.randf() < slip_chance
		var text := ""
		var matches := true

		match qid:
			"q_work":
				if slipped:
					var other: Dictionary = _pick(JOBS, rng)
					while other["occupation"] == p.occupation:
						other = _pick(JOBS, rng)
					text = "%s. Over at %s." % [other["occupation"], other["employer"]]
					matches = false
				else:
					text = "%s. %s." % [p.occupation, p.employer] if p.employer != "—" else "Not working at the minute."
			"q_live":
				if slipped:
					var other_d: String = _pick(DISTRICTS, rng)
					while other_d == p.district:
						other_d = _pick(DISTRICTS, rng)
					text = "%s way. Fifteen minutes on foot." % other_d
					matches = false
				else:
					text = "%s. %s." % [p.district, p.street]
			"q_car":
				if p.vehicle_desc == "None registered":
					if slipped:
						text = "Blue one on the corner. That's mine."
						matches = false
					else:
						text = "I don't drive. Walked."
				else:
					if slipped:
						text = "No, I came on the tram."
						matches = false
					else:
						text = "The %s. Why?" % p.vehicle_desc.split(" (")[0]
			"q_name":
				if slipped:
					text = "%s %s." % [_pick(FIRST_NAMES, rng), _pick(SURNAMES, rng)]
					matches = false
				else:
					text = "%s. It's on the card." % p.full_name

		p.base_answers[qid] = {"text": text, "matches_file": matches, "truth": truth}


## The line they use when they ask for what is under the counter.
static func illicit_line(p: CustomerProfile) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = p.seed_value + 999
	if p.has_tell("wrong_slang"):
		return STALE_SLANG_LINES[rng.randi() % STALE_SLANG_LINES.size()]
	return ILLICIT_LINES[rng.randi() % ILLICIT_LINES.size()]
