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
	"earpiece": {
		"channel": CHANNEL_SCANNER,
		"label": "Something very small in the left ear. It is receiving.",
		"weight": 3,
		"question": "q_ear",
		"prompt": "What's in your ear?",
		"innocent": "Hearing aid. I've worn one since I was nine. Do you want to see the battery?",
		"guilty": "Earphone. I was listening to something. It's off now.",
		"cleared_note": "Hearing loss on the medical file since childhood.",
		"confirmed_note": "Named an earphone that is receiving on no consumer band.",
	},
	"body_armour": {
		"channel": CHANNEL_SCANNER,
		"label": "Dense panel across the chest and back. Under the shirt, not over it.",
		"weight": 3,
		"question": "q_armour",
		"prompt": "You're wearing a vest.",
		"innocent": "Back brace. I lift for a living and my spine's finished. It's medical, I've got the letter.",
		"guilty": "It's a thick jumper. It's cold. Are we finished?",
		"cleared_note": "Occupational back injury logged with the employer.",
		"confirmed_note": "Wearing armour and would not say so.",
	},
	"pocketbook": {
		"channel": CHANNEL_SCANNER,
		"label": "A bound notebook, ruled and numbered. Something written in it tonight.",
		"weight": 2,
		"question": "q_book",
		"prompt": "What are you writing down?",
		"innocent": "Shopping. My memory's gone, I write everything down or I come home with nothing.",
		"guilty": "It's a diary. It's private. You don't get to read my diary.",
		"cleared_note": "Showed the page. It was, in fact, shopping.",
		"confirmed_note": "A numbered pocketbook is not a diary. It is a record.",
	},

	# --- More the terminal turns up -------------------------------------------
	"phone_new": {
		"channel": CHANNEL_TERMINAL,
		"label": "Their telephone number was issued this month.",
		"weight": 2,
		"question": "q_number",
		"prompt": "That number's brand new.",
		"innocent": "Changed provider. The old lot put the price up twice in a year, so I walked.",
		"guilty": "Numbers get changed. People change numbers all the time.",
		"cleared_note": "Provider switch logged, with the old account closed the same week.",
		"confirmed_note": "New number, no closed account behind it. It came from nowhere.",
	},
	"no_utilities": {
		"channel": CHANNEL_TERMINAL,
		"label": "Nothing at that address is in their name. No power, no water, nothing.",
		"weight": 2,
		"question": "q_bills",
		"prompt": "None of the bills at your place are yours.",
		"innocent": "It's my sister's flat. I pay her. I'm not going to start putting my name on her meter.",
		"guilty": "I don't know how the bills work. I just live there.",
		"cleared_note": "Sister listed at the same address, bills in her name.",
		"confirmed_note": "Nobody has lived at that address under that name.",
	},
	"employment_gap": {
		"channel": CHANNEL_TERMINAL,
		"label": "Seven months last year with nothing in the file at all.",
		"weight": 2,
		"question": "q_gap",
		"prompt": "Where were you for seven months last year?",
		"innocent": "Inside. Eight months, out in seven for good behaviour. It's on there, isn't it? It should be on there.",
		"guilty": "Between jobs. It happens. It's not a crime to be between jobs.",
		"cleared_note": "Custodial sentence on the record covering exactly that window.",
		"confirmed_note": "Seven months that neither the file nor the man will account for.",
	},
	"kin_switchboard": {
		"channel": CHANNEL_TERMINAL,
		"label": "Emergency contact is a switchboard number, not a person.",
		"weight": 3,
		"question": "q_kin",
		"prompt": "Who's the number down as your next of kin?",
		"innocent": "The care home. My mother's in Alder House and that's their front desk — she can't hold a phone.",
		"guilty": "My brother. Why? What's it say?",
		"cleared_note": "Alder House. The number matches the home on the file.",
		"confirmed_note": "Named a brother. The number is a departmental switchboard.",
	},

	# --- More you notice while they stand there -------------------------------
	"checks_exits": {
		"channel": CHANNEL_BEHAVIOUR,
		"label": "Looked at your back door before they looked at you.",
		"weight": 2,
		"question": "q_exits",
		"prompt": "That door doesn't go anywhere you need.",
		"innocent": "I thought someone was coming through it. You've got a light on behind there.",
		"guilty": "I wasn't looking at anything. I was looking round.",
		"cleared_note": "There is a light on behind that door. Fair.",
		"confirmed_note": "Found the second exit inside four seconds.",
	},
	"clean_hands": {
		"channel": CHANNEL_BEHAVIOUR,
		"label": "It is below freezing and their hands aren't even red.",
		"weight": 1,
		"question": "q_cold",
		"prompt": "You've not been out in this long.",
		"innocent": "Got dropped off. My shift finishes at the depot and someone runs me down as far as the corner.",
		"guilty": "I walked. I'm just not cold. Some people aren't cold.",
		"cleared_note": "Depot lift is a real arrangement. It's in the shift pattern.",
		"confirmed_note": "Nobody walks this street in February with warm hands.",
	},
	"refuses_bag": {
		"channel": CHANNEL_BEHAVIOUR,
		"label": "Wouldn't take a bag. Wanted it handed over loose.",
		"weight": 2,
		"question": "q_bag",
		"prompt": "You don't want a bag?",
		"innocent": "I've got one in my pocket. I'm not paying you for a bag when I'm carrying a bag.",
		"guilty": "I don't need a bag. It's fine as it is. Just give it to me.",
		"cleared_note": "Produced their own bag, with some satisfaction.",
		"confirmed_note": "Did not want a second thing of yours in their hand.",
	},
	"exact_change": {
		"channel": CHANNEL_BEHAVIOUR,
		"label": "Counted out the exact amount before you'd said the price.",
		"weight": 2,
		"question": "q_exact",
		"prompt": "You knew the price before I said it.",
		"innocent": "I buy the same four things every night of my life. I could do it in my sleep.",
		"guilty": "I guessed. It was a good guess.",
		"cleared_note": "A regular's order, and they knew it to the coin.",
		"confirmed_note": "Came with the money already counted.",
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

	# --- Second pass ----------------------------------------------------------
	#
	# Same rule as everything above it: each of these is something a real
	# customer on this street plausibly has. The tell is never the evidence. The
	# evidence is a tell they cannot account for.

	"radio_stub": {
		"channel": CHANNEL_SCANNER,
		"label": "Short rubber aerial, left hip. Not a phone antenna.",
		"weight": 2,
		"question": "q_radio",
		"prompt": "What's the aerial on your belt?",
		"innocent": "Site radio. I'm night security on the Corn Exchange — I'm on it till six, listen.",
		"guilty": "That's my phone. Everyone's got a phone.",
		"cleared_note": "Turned it on. It is a site channel, and it is dull.",
		"confirmed_note": "Called an aerial a phone while holding the phone.",
	},
	"nitrile_gloves": {
		"channel": CHANNEL_SCANNER,
		"label": "Boxed gloves in the coat. Powder-free, still sealed.",
		"weight": 1,
		"question": "q_gloves",
		"prompt": "That's a lot of gloves for a Tuesday.",
		"innocent": "I do the meat counter at Aldermann's. I take a box home every week, everyone does.",
		"guilty": "For the cold. My hands get bad.",
		"cleared_note": "They do smell faintly of a meat counter.",
		"confirmed_note": "Said gloves were for warmth. They are surgical gloves.",
	},
	"tracker_tag": {
		"channel": CHANNEL_SCANNER,
		"label": "Something in the coat seam answering a ping. It isn't a card.",
		"weight": 3,
		"question": "q_tag",
		"prompt": "Take the coat off a second.",
		"innocent": "It's the shop tag, they never took it out. Cost me forty quid and it beeps at me in every doorway in the city.",
		"guilty": "There's nothing in my coat. Are you going to serve me or not?",
		"cleared_note": "There is a security tag in the seam, unremoved.",
		"confirmed_note": "Refused to hand over a coat that is answering a ping.",
	},
	"cuff_key": {
		"channel": CHANNEL_SCANNER,
		"label": "Small flat key on the ring. Barrel type. Opens nothing domestic.",
		"weight": 2,
		"question": "q_key",
		"prompt": "What's the little flat key for?",
		"innocent": "Meter cupboard. I'm the caretaker for the Halloway blocks, I've got about forty of them.",
		"guilty": "Padlock. On my shed.",
		"cleared_note": "Caretaker on file. Forty keys is about right.",
		"confirmed_note": "Named a padlock. It is not a padlock key.",
	},
	"fresh_notes": {
		"channel": CHANNEL_SCANNER,
		"label": "Wallet is all one denomination. Nothing smaller anywhere on them.",
		"weight": 1,
		"question": "q_notes",
		"prompt": "You've nothing smaller at all?",
		"innocent": "Got paid an hour ago, cash in hand. It's all twenties till I break one.",
		"guilty": "That's what came out of the machine.",
		"cleared_note": "Paid in cash, on file, this week.",
		"confirmed_note": "No machine on this street gives out only these.",
	},

	"licence_endorsed": {
		"channel": CHANNEL_TERMINAL,
		"label": "Driving licence issued four times in six years. Same name each time.",
		"weight": 2,
		"question": "q_licence",
		"prompt": "You've had a lot of licences.",
		"innocent": "I lose things. Ask my wife. That's four replacements and a bill each time, thanks.",
		"guilty": "Have I? News to me.",
		"cleared_note": "Three of the four are logged as replacements, with fees paid.",
		"confirmed_note": "Did not know about four licences in their own name.",
	},
	"no_school": {
		"channel": CHANNEL_TERMINAL,
		"label": "No school, no college, no training. The file starts at twenty-six.",
		"weight": 2,
		"question": "q_school",
		"prompt": "Where'd you go to school?",
		"innocent": "Ravensmoor, then nowhere. I left at fifteen and went on the boats, it's all cash and nobody writes it down.",
		"guilty": "Round here. Local school, you wouldn't know it.",
		"cleared_note": "Named a school that exists and closed the year they say.",
		"confirmed_note": "Could not name the school in their own district.",
	},
	"kin_shares_address": {
		"channel": CHANNEL_TERMINAL,
		"label": "Emergency contact lives at their address but is on no bill there.",
		"weight": 1,
		"question": "q_housemate",
		"prompt": "Who's at the house with you?",
		"innocent": "My brother. He's been on my sofa since March and he pays me in beer, so no, he's not on the gas bill.",
		"guilty": "Nobody. I live on my own.",
		"cleared_note": "Named a brother. There is a brother on file.",
		"confirmed_note": "Says they live alone. Somebody else is registered there.",
	},
	"bank_new": {
		"channel": CHANNEL_TERMINAL,
		"label": "One account, opened this year, and the salary is the only thing in it.",
		"weight": 2,
		"question": "q_bank",
		"prompt": "New in the city?",
		"innocent": "Moved down in January after the yard shut. Everything's new — bank, flat, all of it.",
		"guilty": "I've been here years.",
		"cleared_note": "Address history shows the move, dated January.",
		"confirmed_note": "Claims years here against a file that starts in January.",
	},
	"photo_mismatch": {
		"channel": CHANNEL_TERMINAL,
		"label": "The photograph on file is four years old. They have not aged four years.",
		"weight": 3,
		"question": "q_photo",
		"prompt": "This picture doesn't look like you.",
		"innocent": "I was drinking then. I stopped. That's what two years off it does, and I'll take that as a compliment.",
		"guilty": "Cameras are all rubbish. It's me.",
		"cleared_note": "Record shows a treatment order, ended two years ago.",
		"confirmed_note": "Nothing in the file accounts for the face.",
	},

	"waits_to_be_asked": {
		"channel": CHANNEL_BEHAVIOUR,
		"label": "Hasn't asked for anything. Waiting for you to offer.",
		"weight": 2,
		"question": "q_offer",
		"prompt": "You going to tell me what you want?",
		"innocent": "Sorry — miles away. Twenty of the blue and whatever that is behind you.",
		"guilty": "I thought you'd know what I'm here for.",
		"cleared_note": "Ordered normally the moment they were prompted.",
		"confirmed_note": "Wanted you to name it first. Nobody does that by accident.",
	},
	"reads_the_room": {
		"channel": CHANNEL_BEHAVIOUR,
		"label": "Counted the doors on the way in. You watched them do it.",
		"weight": 2,
		"question": "q_doors",
		"prompt": "You had a good look round on the way in.",
		"innocent": "I got done over in the Kestrel last winter. I look at doors now. You would.",
		"guilty": "Did I? Just looking at the shelves.",
		"cleared_note": "There is an assault on file, at the Kestrel, last winter.",
		"confirmed_note": "Denied doing something you watched them do.",
	},
	"repeats_you": {
		"channel": CHANNEL_BEHAVIOUR,
		"label": "Says your price back to you. Out loud, every time.",
		"weight": 2,
		"question": "q_repeat",
		"prompt": "Why do you keep saying it back?",
		"innocent": "Because I'm half deaf on this side and you all mumble. Say it again, louder.",
		"guilty": "Habit. Doesn't everyone?",
		"cleared_note": "Hearing loss on the medical file. Left side.",
		"confirmed_note": "No hearing note, and they only repeat the numbers.",
	},
	"too_early": {
		"channel": CHANNEL_BEHAVIOUR,
		"label": "Had the money out before they got to the counter.",
		"weight": 1,
		"question": "q_ready",
		"prompt": "You were quick with that.",
		"innocent": "Bus in four minutes and it's the last one. Sorry, I'm not being rude.",
		"guilty": "Just being efficient.",
		"cleared_note": "There is a last bus, and it is in four minutes.",
		"confirmed_note": "In no hurry whatsoever once the money was away.",
	},
	"wrong_hours": {
		"channel": CHANNEL_BEHAVIOUR,
		"label": "Dressed for a day shift, at half three in the morning.",
		"weight": 1,
		"question": "q_hours",
		"prompt": "You're up late for that coat.",
		"innocent": "Been at the hospital since two. My mother's in Ward 9 and I've not been home to change.",
		"guilty": "Couldn't sleep.",
		"cleared_note": "Next of kin is admitted. Ward 9.",
		"confirmed_note": "Nothing explains the clothes or the hour.",
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
	"q_born": {
		"prompt": "What year were you born?",
		"field": "dob",
		"patience": 1,
	},
	"q_ask_employer": {
		"prompt": "Who is it you work for, exactly?",
		"field": "employer",
		"patience": 1,
	},
	"q_street": {
		"prompt": "Whereabouts, then?",
		"field": "street",
		"patience": 1,
	},
	"q_ask_plate": {
		"prompt": "What's the registration?",
		"field": "plate",
		"patience": 1,
	},
	"q_ask_number": {
		"prompt": "What's a number for you?",
		"field": "phone",
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
