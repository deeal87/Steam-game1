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

## How many of the nine standing questions any one person invites. Four leaves
## room on a single page of the dialogue for every tell question a person can
## carry plus every action, so nothing the player needs is ever pushed out of
## reach — and it is already more standing questions than their patience will
## pay for.
const STANDING_QUESTIONS_OFFERED := 4

## Tells that cannot coexist on one person. The second of each pair is dropped.
##
## Two kinds of conflict live here. The first is a contradiction in the fiction:
## `record_scrubbed` means an empty record, so it cannot sit beside any tell
## whose innocent explanation is a line *in* that record — the terminal would
## cite a conviction that is not there, and the honest answer would read as a
## lie.
##
## The second is duller and just as important: two tells that write the same
## field of the file. Whichever ran last would win and the other would leave the
## player looking for something the terminal never printed.
const CONFLICTING_TELLS := [
	# Nothing that writes to the record can survive alongside an empty one.
	["record_scrubbed", "employment_gap"],
	["record_scrubbed", "licence_endorsed"],
	["record_scrubbed", "photo_mismatch"],
	["record_scrubbed", "reads_the_room"],
	# Three tells, one next-of-kin line.
	["kin_switchboard", "kin_shares_address"],
	["kin_switchboard", "wrong_hours"],
	["kin_shares_address", "wrong_hours"],
	# Two tells, one utilities line.
	["no_utilities", "bank_new"],
	# Two tells, one employment note.
	["employment_gap", "no_school"],
]


static func _pick(arr: Array, rng: RandomNumberGenerator) -> Variant:
	return arr[rng.randi() % arr.size()]


## Both of these are used twice: once to write the file, and once to write the
## answer of somebody whose story does not match it. They live here so a wrong
## answer can never be spotted by its *shape* rather than by its contents.
static func _plate(rng: RandomNumberGenerator) -> String:
	return "%s%s %d%d%d" % [
		String.chr(65 + rng.randi() % 26), String.chr(65 + rng.randi() % 26),
		rng.randi() % 10, rng.randi() % 10, rng.randi() % 10,
	]


static func _phone(rng: RandomNumberGenerator) -> String:
	return "07%d%d %d%d%d %d%d%d" % [rng.randi() % 10, rng.randi() % 10,
		rng.randi() % 10, rng.randi() % 10, rng.randi() % 10,
		rng.randi() % 10, rng.randi() % 10, rng.randi() % 10]


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
		p.plate = _plate(rng)
		p.vehicle_desc = "%s %s (%s)" % [_pick(CAR_COLOURS, rng), _pick(CAR_MAKES, rng), p.plate]
	else:
		p.vehicle_desc = "None registered"
		p.plate = "—"

	p.phone = _phone(rng)
	p.phone_registered = _date(rng, 2018, 2025)
	p.next_of_kin = "%s %s (%s)" % [_pick(FIRST_NAMES, rng), _pick(SURNAMES, rng),
		_pick(["sister", "brother", "mother", "father", "partner", "daughter", "son"], rng)]
	p.utilities = _pick([
		"Electricity, water, refuse — all in name",
		"Electricity in name. Water with the landlord",
		"All accounts in name since 2021",
	], rng)
	p.employment_note = "Continuous since %d" % rng.randi_range(2012, 2023)

	var n_record := rng.randi_range(0, 3)
	for i in n_record:
		var entry: String = "%s (%d)" % [_pick(RECORD_POOL, rng), rng.randi_range(2014, 2025)]
		if not p.record.has(entry):
			p.record.append(entry)

	# --- Things you notice without asking ---
	#
	# Drawn from their own hashed stream rather than from `rng`, and that is not
	# fussiness. `kind` is the very first draw off `rng`, so every later value on
	# that stream is conditioned on it — measurably, at two to three standard
	# errors over three thousand profiles. Far too small for a player to spot,
	# but exactly the kind of leak this game must not have: if how big somebody
	# is, or whether they push in, drifts with whether they are police, the game
	# answers its own question through behaviour nobody can help noticing.
	#
	# A separate stream cannot correlate with `kind` at all, which is a better
	# guarantee than a difference that merely measures small today.
	var visible := RandomNumberGenerator.new()
	visible.seed = hash("visible-%d" % seed_value)
	p.height_scale = visible.randf_range(0.90, 1.10)
	p.bulk_scale = visible.randf_range(0.88, 1.18)
	p.pushiness = visible.randf()

	# Which standing questions this person invites. On the same stream for the
	# same reason: the menu is the first thing the player looks at, so if the
	# questions on offer drifted with `kind` the game would be answering itself
	# before a word was said.
	var standing: Array[String] = []
	for qid: String in Tells.BASE_QUESTIONS:
		standing.append(qid)
	for i in range(standing.size() - 1, 0, -1):
		var j := visible.randi() % (i + 1)
		var tmp := standing[i]
		standing[i] = standing[j]
		standing[j] = tmp
	p.standing_questions = standing.slice(0, STANDING_QUESTIONS_OFFERED)

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

	# Some pairs cannot both be true of one person — see CONFLICTING_TELLS.
	#
	# Whichever was picked *later* is the one that goes, rather than always the
	# second of the pair. That matters: an officer's guaranteed non-scanner tell
	# is chosen first and sits at the front of this list, and dropping by pair
	# order could delete exactly that one and leave an officer who gives nothing
	# away except on the scanner.
	for pair: Array in CONFLICTING_TELLS:
		var a := chosen.find(pair[0])
		var b := chosen.find(pair[1])
		if a >= 0 and b >= 0:
			chosen.remove_at(maxi(a, b))

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
	if p.has_tell("phone_new"):
		p.phone_registered = "%d %s 2026" % [rng.randi_range(1, 28), MONTHS[2]]
	if p.has_tell("no_utilities"):
		p.utilities = "No accounts at this address in this name"
	if p.has_tell("employment_gap"):
		p.employment_note = "Seven-month gap, 2025. Unaccounted for."
	if p.has_tell("kin_switchboard"):
		p.next_of_kin = "0800 %d%d %d%d%d%d — switchboard, no name given" % [
			rng.randi() % 10, rng.randi() % 10, rng.randi() % 10,
			rng.randi() % 10, rng.randi() % 10, rng.randi() % 10]
	# An officer whose cover includes a spell inside needs the record to show
	# it, otherwise the honest explanation would contradict their own file.
	if p.has_tell("employment_gap") and p.kind == CustomerProfile.Kind.CIVILIAN:
		p.record.append("Custodial sentence, 8 months (2025)")

	# The second pass of terminal tells, same rule: if the terminal says it, the
	# file has to show it, or the player is reading a claim rather than a record.
	if p.has_tell("licence_endorsed"):
		p.record.append("Driving licence reissued ×4 (2020-2026)")
	if p.has_tell("no_school"):
		p.employment_note = "No education or training record before age 26."
	if p.has_tell("kin_shares_address"):
		p.next_of_kin = "%s %s — same address, not named on any account there" % [
			_pick(FIRST_NAMES, rng), p.full_name.split(" ")[-1]]
	if p.has_tell("bank_new"):
		p.utilities = "Single account, opened %s 2026. Salary credits only." % MONTHS[0]
	if p.has_tell("photo_mismatch"):
		p.record.append("Photograph on file dated 2022, not retaken")

	# The behavioural tells that assert something checkable. Without these the
	# innocent explanation cites a record that is not there, which reads as a lie
	# when the player goes to verify it.
	if p.has_tell("reads_the_room") and p.kind == CustomerProfile.Kind.CIVILIAN:
		p.record.append("Victim of assault, licensed premises (2025)")
	if p.has_tell("wrong_hours") and p.kind == CustomerProfile.Kind.CIVILIAN:
		p.next_of_kin = "%s %s — admitted, St Cuthbert's Ward 9" % [
			_pick(FIRST_NAMES, rng), p.full_name.split(" ")[-1]]


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
			"q_born":
				var year := int(p.dob.split(" ")[-1])
				if slipped:
					# A cover identity's date of birth is the detail that goes
					# first, because it is the one they never had to live with.
					text = "%d. Why?" % (year + [-3, -2, 2, 3][rng.randi() % 4])
					matches = false
				else:
					text = "%d. It's on the card as well, you know." % year
			"q_ask_employer":
				if p.employer == "—":
					if slipped:
						text = "%s. Been there years." % _pick(JOBS, rng)["employer"]
						matches = false
					else:
						text = "Nobody, at the minute. I'm looking."
				elif slipped:
					var other_e: String = _pick(JOBS, rng)["employer"]
					while other_e == p.employer:
						other_e = _pick(JOBS, rng)["employer"]
					text = "%s. Why, do you know it?" % other_e
					matches = false
				else:
					text = "%s. Same crowd eleven years." % p.employer
			"q_street":
				if slipped:
					# Close enough to sound right, wrong enough to check.
					text = "%d %s." % [rng.randi_range(1, 90), _pick(STREETS, rng)]
					matches = false
				else:
					text = "%s. Two minutes that way." % p.street
			"q_ask_plate":
				if p.vehicle_desc == "None registered":
					if slipped:
						text = "%s. It's round the corner." % _plate(rng)
						matches = false
					else:
						text = "Haven't got one. I don't drive."
				elif slipped:
					# A registration is six characters somebody else chose for
					# you. Nobody rehearsing a cover gets it wrong by a mile —
					# they get it wrong by a digit.
					text = "%s, I think. I never look at it." % _plate(rng)
					matches = false
				else:
					text = "%s. Why?" % p.plate
			"q_ask_number":
				if slipped:
					text = "%s. Ring it if you like." % _phone(rng)
					matches = false
				else:
					text = "%s. Not that you'll ever ring it." % p.phone

		p.base_answers[qid] = {"text": text, "matches_file": matches, "truth": truth}


## The line they use when they ask for what is under the counter.
static func illicit_line(p: CustomerProfile) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = p.seed_value + 999
	if p.has_tell("wrong_slang"):
		return STALE_SLANG_LINES[rng.randi() % STALE_SLANG_LINES.size()]
	return ILLICIT_LINES[rng.randi() % ILLICIT_LINES.size()]
