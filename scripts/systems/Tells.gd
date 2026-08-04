class_name Tells
extends RefCounted
## The evidence database.
##
## Design note, because this is the part that decides whether the game is fun:
##
## No single signal identifies an undercover officer. Every tell an officer can
## leak is also something an innocent person can plausibly have — plenty of
## people on this street carry a gun, and plenty have a clean record. What
## separates them is that a civilian can *explain* their tell, and an officer
## cannot. So the loop is: find a tell with the scanner or the terminal, use it
## to unlock a question, then judge the answer against the file.
##
## Each question costs patience. You cannot simply ask everything.

const CHANNEL_SCANNER := "scanner"
const CHANNEL_TERMINAL := "terminal"
const CHANNEL_BEHAVIOUR := "behaviour"

## weight is how much this contributes to a confident read once it is
## unexplained. Anything at 3 is close to conclusive on its own.
const CATALOGUE := {
	# --- Things the handheld scanner picks up ---------------------------------
	"concealed_firearm": {
		"channel": CHANNEL_SCANNER,
		"label": "Metal signature at the right hip. Holstered, under the coat.",
		"weight": 1,
		"question": "q_carry",
		"prompt": "You're carrying. What for?",
		"innocent": "Yeah. Licensed, it's on the card. I unload trucks on Vane Street till four in the morning — you'd carry too.",
		"guilty": "I'm not carrying anything. ...It's a belt buckle. Your machine's broken.",
		"cleared_note": "Firearms licence checks out against the file.",
		"confirmed_note": "Denied a weapon the scanner is still reading.",
	},
	"body_wire": {
		"channel": CHANNEL_SCANNER,
		"label": "Active transmitter, centre chest. Something is listening.",
		"weight": 3,
		"question": "q_wire",
		"prompt": "What's the box under your shirt?",
		"innocent": "Heart monitor. Had a scare in March, they make me wear it for a year. You want to see it?",
		"guilty": "Insulin pump. ...Diabetes. It's private, alright?",
		"cleared_note": "Medical device on file, dated March. Consistent.",
		"confirmed_note": "Named a medical device that is not in their medical file.",
	},
	"badge": {
		"channel": CHANNEL_SCANNER,
		"label": "Flat shield-shaped metal, inner left pocket.",
		"weight": 3,
		"question": "q_badge",
		"prompt": "Empty the inside pocket for me.",
		"innocent": "It's a hip flask. Look — it's a flask. Are we doing this or not?",
		"guilty": "There's nothing in that pocket. Just ring it up, will you?",
		"cleared_note": "Showed the flask. Shape matches the reading.",
		"confirmed_note": "Refused to open a pocket the scanner reads metal in.",
	},
	"burner_phone": {
		"channel": CHANNEL_SCANNER,
		"label": "Two handsets. One of them isn't on any network.",
		"weight": 2,
		"question": "q_phone",
		"prompt": "Two phones?",
		"innocent": "Work gives me one. I'm not putting the depot's number on my own line, am I?",
		"guilty": "One's dead. Old one. I keep meaning to bin it.",
		"cleared_note": "Second number registered to their employer.",
		"confirmed_note": "Second handset is on no network at all, live or dead.",
	},
	"sample_kit": {
		"channel": CHANNEL_SCANNER,
		"label": "Sealed containers in the bag. Sterile, unopened.",
		"weight": 3,
		"question": "q_kit",
		"prompt": "What's in the tubes?",
		"innocent": "Urine sample pots. I'm on a programme. Twice a week I have to go and fill one. It's humiliating, thanks for asking.",
		"guilty": "Nothing. Empties. I collect them.",
		"cleared_note": "Enrolled on a supervised programme. Explains the pots.",
		"confirmed_note": "Could not account for sterile evidence containers.",
	},
	"marked_cash": {
		"channel": CHANNEL_SCANNER,
		"label": "Notes in the wallet run in sequence. Straight from a bank strap.",
		"weight": 2,
		"question": "q_cash",
		"prompt": "Where'd the cash come from?",
		"innocent": "Drew it out Friday. Cashed the whole wage packet, the machine gives you them in order.",
		"guilty": "It's just money. Does it matter where money comes from in a place like this?",
		"cleared_note": "Wage payment on file, Friday, matching amount.",
		"confirmed_note": "Would not say where a bank-strapped bundle came from.",
	},

	# --- Things the terminal turns up -----------------------------------------
	"employer_front": {
		"channel": CHANNEL_TERMINAL,
		"label": "Employer has no premises, no filings, and one employee.",
		"weight": 2,
		"question": "q_employer",
		"prompt": "Your firm doesn't seem to have an address.",
		"innocent": "It's my brother-in-law's. It's two vans and a lock-up, it's not exactly a corporation.",
		"guilty": "We're a contractor. We work on-site. There's nothing to have an address for.",
		"cleared_note": "Small family firm. Thin, but real.",
		"confirmed_note": "Employer exists only on paper.",
	},
	"address_precinct": {
		"channel": CHANNEL_TERMINAL,
		"label": "Home address sits inside the block the department leases.",
		"weight": 2,
		"question": "q_block",
		"prompt": "Roth Street. That's department housing, isn't it?",
		"innocent": "Half that block is council. My mum's had that flat since before they took the rest of it.",
		"guilty": "It's just a block of flats. I don't know who owns it. Who owns yours?",
		"cleared_note": "Tenancy predates the department's lease by nine years.",
		"confirmed_note": "Lives in department housing and would not say so.",
	},
	"record_scrubbed": {
		"channel": CHANNEL_TERMINAL,
		"label": "No record of any kind. Not a fine, not a caution, not a parking ticket.",
		"weight": 1,
		"question": "q_record",
		"prompt": "Forty years old and never so much as a ticket?",
		"innocent": "I don't drive and I don't drink. It's not a talent, it's just a boring life.",
		"guilty": "Is that a problem? I'd have thought a clean record was the good outcome.",
		"cleared_note": "No licence, no vehicle. A clean sheet makes sense.",
		"confirmed_note": "A file this empty has usually been emptied.",
	},
	"id_recent": {
		"channel": CHANNEL_TERMINAL,
		"label": "Identity card issued in the last three weeks.",
		"weight": 2,
		"question": "q_id",
		"prompt": "This card's three weeks old.",
		"innocent": "Got my bag lifted on the tram. Took them a month to send a new one, and they charged me for it.",
		"guilty": "They expire. You renew them. That's how it works.",
		"cleared_note": "Theft reported to the tram operator. Replacement fee logged.",
		"confirmed_note": "Old card had four years left. Nothing prompted a reissue.",
	},
	"vehicle_fleet": {
		"channel": CHANNEL_TERMINAL,
		"label": "Plate returns to a municipal pool vehicle.",
		"weight": 2,
		"question": "q_plate",
		"prompt": "That plate's a city motor.",
		"innocent": "I drive for the city. Refuse collection. They let us take them home on nights.",
		"guilty": "Borrowed it. Mate of mine. Look, do you want to sell me something or not?",
		"cleared_note": "Employed by city sanitation. Take-home vehicle is standard.",
		"confirmed_note": "No connection on file to the city, but drives its car.",
	},
	"file_thin": {
		"channel": CHANNEL_TERMINAL,
		"label": "One photograph on file. Taken this year. Nothing before it.",
		"weight": 2,
		"question": "q_history",
		"prompt": "There's nothing on you from before this year.",
		"innocent": "I lived abroad. Came back in the spring. It's all in the other country's system, not yours.",
		"guilty": "I don't know what to tell you. I've always been here.",
		"cleared_note": "Re-entry stamp in the spring. The gap is real.",
		"confirmed_note": "Claims lifelong residence with no record of it.",
	},

	# --- Things you notice while they stand there -----------------------------
	"camera_glance": {
		"channel": CHANNEL_BEHAVIOUR,
		"label": "Keeps finding the camera in the corner. Twice now.",
		"weight": 1,
		"question": "q_camera",
		"prompt": "Something interesting up there?",
		"innocent": "You've got it pointed at the till and not the door. Anyone comes in here, you'll have a lovely picture of your own hands.",
		"guilty": "I was reading the sign. There's a sign next to it.",
		"cleared_note": "Fair point about the camera, honestly.",
		"confirmed_note": "There is no sign next to the camera.",
	},
	"wrong_slang": {
		"channel": CHANNEL_BEHAVIOUR,
		"label": "Asked for it by a name nobody's used round here in ten years.",
		"weight": 2,
		"question": "q_slang",
		"prompt": "Nobody's called it that since I was at school.",
		"innocent": "I'm forty-six. I'm going to call it what I called it when I started.",
		"guilty": "That's what it's called. That's what everyone calls it.",
		"cleared_note": "Old enough for the old word. Checks out.",
		"confirmed_note": "Learned the word somewhere other than this street.",
	},
	"no_haggle": {
		"channel": CHANNEL_BEHAVIOUR,
		"label": "Took the first price without a flicker. Nobody does that.",
		"weight": 1,
		"question": "q_price",
		"prompt": "You didn't even ask what it costs.",
		"innocent": "I've been awake for twenty hours. Charge me double, I don't care.",
		"guilty": "The price is the price. I'm not going to argue with you about it.",
		"cleared_note": "Genuinely too tired to care.",
		"confirmed_note": "Not spending their own money.",
	},
	"squared_up": {
		"channel": CHANNEL_BEHAVIOUR,
		"label": "Stands square-on to you, both hands free, back to the wall.",
		"weight": 2,
		"question": "q_stance",
		"prompt": "You can put your bag down, you know.",
		"innocent": "I got jumped on this street in February. I stand where I can see the door now. No offence.",
		"guilty": "I'm comfortable. Are you going to serve me?",
		"cleared_note": "Assault reported on this street in February. Same person.",
		"confirmed_note": "Trained stance, and no reason on file to have one.",
	},
	"lingering": {
		"channel": CHANNEL_BEHAVIOUR,
		"label": "Paid, and then didn't leave.",
		"weight": 1,
		"question": "q_linger",
		"prompt": "Was there something else?",
		"innocent": "Waiting for the rain to give up. I'll stand outside if I'm in the way.",
		"guilty": "No. No, I'm going.",
		"cleared_note": "It is, in fairness, raining.",
		"confirmed_note": "Left the moment they were asked why they were still there.",
	},
}

## When someone neither explains a tell nor admits to it. Used for a civilian
## who is too rattled, drunk or fed up to give you a straight answer — which is
## how an innocent person ends up looking exactly like an officer.
const EVASIVE := [
	"...Does it matter? I just want to pay and go.",
	"I've been up since five. I'm not doing this.",
	"Why are you asking me that? Nobody else asks me that.",
	"Is this a shop or an interview?",
	"Forget it. Forget I said anything.",
	"That's — no. I'm not answering that.",
]

const EVASIVE_NOTE := "Didn't answer. Could be anything."


## Questions that are always on the menu. These do not need a tell to unlock,
## and their answers are checked against the terminal file rather than against
## a tell — which is why looking someone up before you talk to them matters.
const BASE_QUESTIONS := {
	"q_work": {
		"prompt": "What is it you do?",
		"field": "occupation",
		"patience": 1,
	},
	"q_live": {
		"prompt": "You live local?",
		"field": "district",
		"patience": 1,
	},
	"q_car": {
		"prompt": "That your car out front?",
		"field": "vehicle_desc",
		"patience": 1,
	},
	"q_name": {
		"prompt": "I didn't catch your name.",
		"field": "full_name",
		"patience": 1,
	},
}


static func get_tell(id: String) -> Dictionary:
	return CATALOGUE.get(id, {})


static func ids_for_channel(channel: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in CATALOGUE:
		if CATALOGUE[id]["channel"] == channel:
			out.append(id)
	return out


static func all_ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in CATALOGUE:
		out.append(id)
	return out
