class_name CustomerProfile
extends RefCounted
## One person, and everything knowable about them.
##
## The terminal reads from this. So does the scanner, the dialogue, and the
## judgement you make at the end. There is no separate hidden "is a cop" flag
## the systems consult behind your back: `kind` is set at generation and every
## observable consequence flows from the tells attached here.

enum Kind { CIVILIAN, UNDERCOVER }

var seed_value: int = 0
var kind: Kind = Kind.CIVILIAN

# --- Identity ---
var full_name: String = ""
var age: int = 30
var dob: String = ""
var id_number: String = ""
var id_issued: String = ""
var id_expires: String = ""
var street: String = ""
var district: String = ""
var occupation: String = ""
var employer: String = ""
var vehicle_desc: String = ""
var plate: String = ""
var record: Array[String] = []

# --- Appearance ---
var height_scale: float = 1.0
var bulk_scale: float = 1.0

# --- What they want ---
var order: Array[String] = []
var wants_illicit: bool = false
var illicit_units: int = 1
var greeting: String = ""

# --- Tells ---
## tell_id -> {discovered: bool, asked: bool, outcome: "" | "cleared" | "confirmed"}
var tells: Dictionary = {}

# --- Interrogation ---
## Chance that an officer's cover survives a question about a tell. The
## department built them a real licence, a real tenancy, a real medical file —
## so sometimes the innocent explanation is fully documented and checks out.
## This is what stops questioning from being an oracle.
var cover_strength: float = 0.0
## Chance that an innocent person fails to explain themselves. Tired, drunk,
## insulted, or simply not willing to justify their own possessions to a
## shopkeeper at three in the morning.
var nerves: float = 0.15

var patience: int = 5
var patience_max: int = 5
var aborted: bool = false          ## Walked out because you pushed too hard.
var base_answers: Dictionary = {}  ## qid -> {text, matches_file}
var asked_base: Dictionary = {}    ## qid -> true

# --- Session state ---
var scanned: bool = false
var looked_up: bool = false
var served: bool = false
var sold_illicit: bool = false


func has_tell(id: String) -> bool:
	return tells.has(id)


func tell_state(id: String) -> Dictionary:
	return tells.get(id, {})


func discover(id: String) -> bool:
	if not tells.has(id):
		return false
	if tells[id]["discovered"]:
		return false
	tells[id]["discovered"] = true
	return true


func discovered_tells(channel: String = "") -> Array[String]:
	var out: Array[String] = []
	for id: String in tells:
		if not tells[id]["discovered"]:
			continue
		if channel != "" and Tells.get_tell(id).get("channel", "") != channel:
			continue
		out.append(id)
	return out


## Tells this person actually has on the given channel, whether or not the
## player has found them yet. Used by the scanner and terminal to decide what
## to reveal.
func tells_on_channel(channel: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in tells:
		if Tells.get_tell(id).get("channel", "") == channel:
			out.append(id)
	return out


# --- Interrogation -----------------------------------------------------------

## Questions currently on the menu: the four standing ones, plus one unlocked
## by each tell the player has actually found.
func available_questions() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for qid: String in Tells.BASE_QUESTIONS:
		if asked_base.has(qid):
			continue
		out.append({
			"id": qid,
			"prompt": Tells.BASE_QUESTIONS[qid]["prompt"],
			"kind": "base",
		})
	for id: String in tells:
		var st: Dictionary = tells[id]
		if not st["discovered"] or st["asked"]:
			continue
		var t := Tells.get_tell(id)
		out.append({
			"id": t["question"],
			"prompt": t["prompt"],
			"kind": "tell",
			"tell": id,
		})
	return out


## Rolls for this profile only, seeded from the profile, so a given person
## answers a given question the same way however the night plays out.
var _rng: RandomNumberGenerator = null

func _roll() -> float:
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.seed = seed_value * 31 + 17
	return _rng.randf()


## Returns {text, note, outcome, aborted}.
##
## An answer is not proof. Three things can come back:
##
##   confirmed — they contradicted themselves or refused. That is real.
##   cleared   — the explanation holds up against the file. Usually true, but
##               a well-built cover clears too.
##   unclear   — they didn't answer. Common enough among innocent people that
##               it can never be treated as guilt on its own.
func ask(entry: Dictionary) -> Dictionary:
	patience -= 1

	var result := {"text": "", "note": "", "outcome": "", "aborted": false}

	if entry["kind"] == "tell":
		var tid: String = entry["tell"]
		var t := Tells.get_tell(tid)
		tells[tid]["asked"] = true
		var roll := _roll()

		if kind == Kind.UNDERCOVER:
			if roll < cover_strength:
				# Cover held. The paperwork backs the story, and it is the
				# paperwork you are checking against.
				tells[tid]["outcome"] = "cleared"
				result["text"] = t["innocent"]
				result["note"] = t["cleared_note"]
				result["outcome"] = "cleared"
			else:
				tells[tid]["outcome"] = "confirmed"
				result["text"] = t["guilty"]
				result["note"] = t["confirmed_note"]
				result["outcome"] = "confirmed"
		else:
			if roll < nerves:
				tells[tid]["outcome"] = "unclear"
				result["text"] = Tells.EVASIVE[int(_roll() * Tells.EVASIVE.size()) % Tells.EVASIVE.size()]
				result["note"] = Tells.EVASIVE_NOTE
				result["outcome"] = "unclear"
			else:
				tells[tid]["outcome"] = "cleared"
				result["text"] = t["innocent"]
				result["note"] = t["cleared_note"]
				result["outcome"] = "cleared"
	else:
		var qid: String = entry["id"]
		asked_base[qid] = true
		var ans: Dictionary = base_answers.get(qid, {"text": "...", "matches_file": true})
		result["text"] = ans["text"]
		if ans["matches_file"]:
			result["note"] = "Matches the file."
			result["outcome"] = "consistent"
		else:
			result["note"] = "Does not match the file."
			result["outcome"] = "contradiction"

	if patience <= 0:
		aborted = true
		result["aborted"] = true
	return result


# --- Reading the evidence ----------------------------------------------------

## What the player has actually established, weighted. This drives the
## notebook's summary line. It never reveals `kind` directly — a cautious
## officer can leave with a low score, and an unlucky civilian with a high one.
func suspicion_score() -> int:
	var score := 0
	for id: String in tells:
		var st: Dictionary = tells[id]
		if not st["discovered"]:
			continue
		var w: int = Tells.get_tell(id).get("weight", 1)
		match st["outcome"]:
			"confirmed": score += w * 2
			"cleared": score -= w
			"unclear": score += w    # asked, and got nothing back
			_: score += w            # found but not yet put to them
	for qid: String in asked_base:
		var ans: Dictionary = base_answers.get(qid, {})
		if not ans.get("matches_file", true):
			score += 3
	return score


func read_out() -> String:
	var s := suspicion_score()
	if s <= 0:
		return "Nothing on them."
	elif s <= 3:
		return "One or two odd things."
	elif s <= 7:
		return "Enough to be careful."
	elif s <= 12:
		return "This does not add up."
	return "This is a police officer."


func evidence_lines() -> Array[String]:
	var out: Array[String] = []
	for id: String in tells:
		var st: Dictionary = tells[id]
		if not st["discovered"]:
			continue
		var t := Tells.get_tell(id)
		var line: String = "· " + str(t["label"])
		match st["outcome"]:
			"cleared": line += "\n    → " + str(t["cleared_note"])
			"confirmed": line += "\n    → " + str(t["confirmed_note"])
			"unclear": line += "\n    → " + Tells.EVASIVE_NOTE
			_: line += "\n    → Not put to them yet."
		out.append(line)
	for qid: String in asked_base:
		var ans: Dictionary = base_answers.get(qid, {})
		if not ans.get("matches_file", true):
			out.append("· Answer to \"%s\" contradicts the file." % Tells.BASE_QUESTIONS[qid]["prompt"])
	return out


func address_line() -> String:
	return "%s, %s" % [street, district]
