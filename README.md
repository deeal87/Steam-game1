# Kiosk At Midnight

A lonely kiosk on a dark street. Nothing else for a mile in any direction.

You keep the shelves full and the lights on. You also keep something under the
counter, which is the only reason the rent gets paid. Some of the people who
come to the window are police, and they are here to buy from you once.

You have a scanner, a registry terminal, and however many questions they will
stand for. Work out who they are before you decide what to sell them.

A first-person shift-survival game in the shape of *Shift At Midnight*, built
in Godot 4.3 for Windows, Linux and macOS.

---

## The place

You are not sealed in one room. It is a **shop**: ten metres by eight, with a
front door customers walk in through, three racks with aisles round them, a
checkout island with a customer side and a staff side, a **stockroom** behind
holding every case you have not put out yet, and a **manhole** in its floor.

Outside is about a hundred metres of street you can walk all of. The working
lamps thin out as you go west until there are none. Underneath it all is a
small network of brick sewer: a main run west from the stockroom, two ladders
up to the street, and a spur that goes nowhere in particular.

```
           [hatch]         [shop door]
     +--------[==]------------[  ]--------+
     | [rack]                    [rack]   |
     |           [island rack]            |   customers browse here
     |                                    |
     |   ==========CHECKOUT==========     |
     |            staff side              |
     +-----------[stockroom]--------------+
                      |
            +---------+----------+
            |     STOCKROOM      |
            | [pallet racks] (O) |   (O) manhole
            +--------------------+        |
                                          v
     ==========================================  sewer, 55 m west
              |             |             |
        far ladder    middle ladder   (spur, dead end)
```

Carry the **torch** (`T`). The kiosk is the only lit room in the game, and once
you can leave it the street and the sewer are genuinely dark.

## The loop

One night is one shift, 23:00 to 05:00.

1. **Trade.** Up to four people are in the shop at once. They walk in, browse
   at their own pace, and join the back of the queue when they are done — so
   the order they reach your counter is not the order they came in. Only the
   person at the front is served; everyone behind can still be swept and looked
   up while they wait, which is the point of a queue. They take what they want
   off the racks themselves and put it on the counter. **Scan each item** (`E`), which rings up the price and
   drops it in the bag, then **work the till** — which refuses while anything is
   still unscanned. Restock from the stockroom when a run empties: an empty
   shelf is a customer who arrives at the counter with nothing. Shelf trade
   alone never quite covers the rent.
2. **The ask.** Roughly a third of customers — and *every* undercover officer —
   will also ask for what is under the counter. This is where the money is.
3. **Decide.** Sweep them with the scanner. Pull their file on the terminal.
   Watch how they stand. Ask questions, and check the answers against the file.
   Then sell, refuse, send them away, or shoot them.
4. **Consequences.** Kill an officer and the round is yours. Let one walk and a
   door team comes back between shifts — a hard one if they left with a buy, a
   lighter one if they left empty-handed. Shoot a civilian and you get the raid
   *and* the heat.
5. **Settle up.** Being wrong about someone is billed at 05:00, before the rent
   (see below).
6. **Survive the raid**, pay the rent, and the next night is worse.

### What people are wearing

The character sheet is fifty-five whole figures standing in rows — presentation
renders of models rather than a grid of material samples — so there is nothing on
it that lifts straight onto a surface. What lifts is the clothes. A figure is
about 55 by 180 pixels, which makes a jacket roughly 46 by 62 and a pair of
trousers 40 by 70; that sounds tiny and is not, because the whole world renders
into a 426x240 buffer and a jacket at 46 across is already finer than the screen
it is drawn on. Sixteen sets come off the sheet, two from each row, so the crowd
is a mix of the ages and trades the artist drew rather than sixteen versions of
the same person.

The faces cannot be taken and should not be. A head on that sheet is 21 by 26
pixels with maybe four by five of actual face in it, against the 32 by 32 the
generator paints with eyes and a mouth deliberately placed — and a fixed set of
painted faces would have two people in one night wearing the same face. Clothing
is shared on purpose and always has been; the face is the thing this game asks
you to remember.

Which is why **the outfit moved onto the hashed per-person stream**, beside height
and build. `ProcMesh.human` used to pick it itself from a generator seeded with
`seed_value` — the same value whose first draw decides whether somebody is police
— so the two came out of the same underlying state. Nothing measurable came of
that while every outfit was a slightly different shade of dark. A tweed jacket,
a set of overalls and a shirt and tie is a different proposition: it is the most
visible thing about a person before they have said a word, so it is now held to
the same test as everything else a player perceives without investigating, and it
is measured as the outfit *worn* rather than as the raw draw behind it — two
distributions with identical means can disagree completely once folded into
sixteen.

The draw is taken last, after everything else that reads that stream. Putting it
in beside the other appearance traits pushed every later draw along by one and
moved `nerves` from 0.9 standard errors off `kind` to 1.9 — still inside
tolerance, and no reason to spend the margin.

## Reading people

**No single signal identifies an officer.** Every tell one can leak is
something an innocent person can also have. Plenty of people on this street
carry a gun; plenty have a clean record. The difference is that a civilian can
*explain* their tell and an officer usually cannot.

Evidence arrives on four channels:

| Channel | How you get it | Example |
|---|---|---|
| **Scanner** | `F` while pointing at them | A transmitter, centre chest |
| **Terminal** | pull their registry file | Employer with no premises and one employee |
| **Behaviour** | just watch them | Keeps finding the camera in the corner |
| **Their answers** | ask, and check against the file | Says bakery, file says city services |

There are **43 tells** — fourteen on the scanner, fifteen on the terminal,
fourteen in how somebody behaves — and **nine standing questions**, of which any
one person invites four. That subset is why two customers in a row do not feel
like the same conversation, and it keeps the menu short enough to read while
somebody is waiting.

Finding a tell unlocks a question about it. Asking costs patience, and patience
runs out — you cannot ask everything, so you have to choose which contradiction
is worth spending a question on. An answer comes back **confirmed** (they
contradicted themselves), **cleared** (the explanation holds up), or
**unclear** (they didn't answer, which innocent people do often enough that it
can never be treated as guilt on its own).

Officers get better as the nights go on. Not more numerous — *better covered*.
Their documents start holding up to questions that would have broken them on
night three, which is the main reason the game gets harder.

## Being wrong about people

Guessing has to cost something, or the game has an obvious answer: throw
everybody out, sell to nobody, never get raided. So the shift report bills you
for the people you were wrong about, itemised rather than as a lump sum.

| What you did | Your name | Cash |
|---|---|---|
| Sent a regular customer away | −7% | −30 |
| Shot a regular customer | −28% | −110 |
| Sent an officer away | nothing | nothing |
| A whole night without a mistake | +5% | — |
| Somebody gave up queueing | −2.5% | not billed |

**Your name on the street** is the meter marked `NAME` in the corner. It decides
how many people bother walking down here tomorrow — at a ruined name you get
roughly 45% fewer customers, which is fewer baskets, fewer tips and fewer people
who might ask for what's under the counter. It compounds: a bad night makes the
next night thinner, and a thin night is harder to make rent on.

Refusing the ask is always free. Refusing the *person* is not. The distinction
is the whole game: you can decline to sell to anyone you're unsure about and
still take their shopping, and that costs you only the margin.

The three-strategy check in `tests/BalanceTest.gd` exists to prove the rule
holds. Over five nights: serving the ask earns ~2300 and never misses rent,
refusing every ask earns ~320 and misses rent four nights in five, and throwing
everybody out earns nothing, misses every night, and ends with a name at 0%.

## What you do with the body

Shooting somebody used to cost a mouse click. A bag was spent automatically, a
little heat came off, and three and a half seconds later they were gone — so
the worst thing you can do in this game took less work than ringing up a packet
of crisps.

They stay where they fell now, and dealing with them is three steps you have to
find time for while the queue is still coming in:

1. **Bag them.** Costs a body bag, which you had to have bought.
2. **Pick them up.** Fills both hands — no scanner, no weapon, no serving —
   and slows you to a walk.
3. **Put them down the manhole.** That is the only place one goes.

The pressure comes from what happens if you don't. **Anyone who gets near an
unbagged body bolts**: they leave without paying, it costs you heat and your
name, and it counts as evidence. Each person only reacts once, so standing next
to one is not a per-frame drain — but every new customer through the door is a
fresh one.

Bagging stops the panic. It does not get rid of them. **Close up at 05:00 with
one still on the floor and it is evidence**, at +26 heat for a dead customer
and +10 for a dead officer — the difference being that there is nobody left to
explain why the customer is dead.

Getting one down the manhole takes some heat back off, but never all of it. The
heat from pulling the trigger is not refundable; only the extra you earn by
leaving them where they landed.

## The raid

When the shutter fails they throw something through the hatch, and there is a
beat of white before the first man follows it. They come through **in pairs**,
not as one crowd — eight people arriving simultaneously in a room four metres
wide is not a firefight, it is a cutscene where you lose.

They shoot at where they last *saw* you, not where you are. Crouching behind
the counter genuinely breaks their line, and there is a beat between them
acquiring you and pulling the trigger, so stepping into a doorway is a
mistake rather than an execution. The room's geometry is the weapon.

**They come in pairs, and the pair has a job each.** The first through takes
**point**: he closes on you, going wide round the end of the counter island
rather than up the middle into your shotgun. The second is his **cover**: he
stops a pace inside the door with a line across the room and fires the moment
you show yourself. He does not go looking for you — leaving his angle is how a
doorway becomes free — and because he is standing still he shoots noticeably
better than the man who is moving.

That pairing is the difficulty of the fight. Against two people with no plan you
could hold one angle and win. Against a point and a cover, staying still gets
you flushed and moving gets you shot, so you have to decide which of the two to
spend your shells on. Kill the point and his cover stops covering and comes on
himself — otherwise shooting one man per wave would clear the room.

**With both doors open they take one each**, which is the clearest argument for
paying to close one: a single approach means the pair has to funnel, and a
funnel is a thing you can point a shotgun at.

**They share what they see.** One of them getting eyes on you calls it in, and
everybody walks to that, whether or not they saw it themselves. Breaking line of
sight with the man in front of you no longer means the man behind him has lost
you. Called-in positions go stale after a few seconds, though — a team that
never forgets is one you can never escape.

Three fittings from the supplier change the shape of the fight:

| | |
|---|---|
| **Barricade** | Roughly doubles how long the shutter holds |
| **Window bars** | Closes the hatch as an entrance, so the whole team has to funnel through the back door — much easier to point a shotgun at |
| **Bear trap** | Takes the first one through, whichever door that is |

### What the raid team is wearing

They used to be plain black boxes with a green strip for a visor. The silhouette
was right — the intent is that a unit reads as a shape in the dark until its
torch swings onto you — and everything inside the silhouette was nothing.

The pack's police gear sheet is the closest thing it has to character art, and
none of it was being used: a vest, body armour, a helmet, a gas mask and a riot
shield were sitting on the sheet while the team wore flat metal. They are on now.
Which kit an officer is issued comes off their place in the squad rather than off
a die, so a team looks like a team that was equipped rather than five people who
dressed at random, and whoever goes through the door first carries the shield.

The vest goes on as a panel over the chest rather than as the torso's own
texture. The torso is a box, and a box wears its texture on all six faces —
including the back and the tops of the shoulders, where a photograph of the front
of a vest is nonsense. The mask keeps a little of the old visor's glow for the
same reason the visor existed: there has to be something to catch your eye in a
dark room, and a photograph of a gas mask is very dark indeed.

All of it is optional. Without the pack this is the same black silhouette it has
always been, rather than a missing texture.

## The queue

Four marks on the floor: one at the till, three behind it. Someone is always
watching you work, and the person third in line is someone you can have
already scanned and read the file on by the time they reach you. Waiting burns
their patience too — leave a queue standing and people put the basket down and
walk out. That costs a little of your name: not a mistake, just slow, and
priced well below being wrong about somebody.

**The order does not hold.** Everybody has a *pushiness*, and standing behind
somebody winds them up in proportion to it. Enough of that and they step
forward one place. The person they stepped in front of loses patience over it
and gets readier to do the same to whoever is now ahead of them, so a busy
queue churns rather than swapping one pair and settling. Two rules keep it from
becoming noise: nobody is ever stepped in front of at the counter itself, and
only one swap happens per frame.

The reason it matters is that the queue is your reading order. You scanned the
person third in line and started on their file; now they are second and the
one you had not looked at yet is about to be standing in front of you.

**Pushiness is drawn from a stream that cannot correlate with whether they are
police** — as are height and build. Anything a player perceives without
investigating has to be independent of the answer, or the game gives itself
away through a behaviour nobody can help noticing. The smoke suite measures all
four such traits and fails if officers and civilians differ by as much as two
standard errors. That test is not decoration: it caught a real 2.3-sigma bias
the first time it ran, because these traits were being drawn off the same
random stream that had already decided who was police.

### Getting round the shop

A customer steers in a straight line at whatever they want next and slides off
whatever they hit. That is enough almost everywhere in a room this size, and it
is not enough for the island rack: the line from the right-hand shelving to the
left-hand shelving runs the length of it, so anybody wanting something off both
ended up pressed into the middle of the shelves for the whole walk. From the
floor that reads as people standing inside the furniture, which is what it was
reported as.

The world knows where its shelving is, as flat rectangles on the floor plan.
Before each leg of a shopper's route is committed, it is asked whether walking
it goes through one — and if it does, the leg is split around the near end of
that rack, on the aisle side. Round the near end rather than whichever end makes
the total journey shortest: from the right-hand rack the far corner of the
island is a hair closer overall and the walk to it goes straight down the middle
of the shelving. The split repeats on the new legs, so going round one rack onto
a line that crosses the next is handled without any of it knowing about the
floor plan in particular.

The smoke suite walks every leg anyone could ever take, in both directions, and
fails if any of them passes through a rack — the routing is the fix, and a
simulated shopper who happens not to want anything off both wall racks would
prove nothing either way.

The collision capsule was also narrower than the person drawn on it. `human()`
builds a body 0.42 × bulk across with the arms outside that, so above bulk 1.0
the capsule stopped at the shelf and the shoulder carried on into it.

## The checkout

The reason this is worth doing by hand rather than by pressing "sell": you have
to keep your eye on the counter while you are also deciding whether the person
across it is police. The till display shows `scanned / total` and the running
price, and the till will not open until those match.

Nothing stops you skipping an item. It just means you handed it over for free.

## The tunnels

Not a corridor with a ladder at each end. A main run of brick heads west from
the stockroom manhole, and three things hang off it:

```
   stockroom manhole
          |
  ========+=====================+==========+=======  main run, west
                                |          |
                          [spur]|          |
                          crate |          +-- dogleg south
                                              to the FAR ladder
                    +-- dogleg south
                        to the MIDDLE ladder
```

That gives the trip a decision instead of a walk:

- **The middle ladder** is much shorter, and puts you back on the open pavement
  within sight of your own front door. Which is the last place you want to be
  standing on the night you went down there to get away from it.
- **The far ladder** is a long way past everything living down there, and comes
  up in the dark corner at the end of the road where nobody is looking.
- **The spur** goes nowhere. There is a crate at the end of it worth roughly a
  night's rent, once per run, and from the third trip onward there is something
  waiting between you and it.

The crate is deliberately once per run rather than once per trip. If it
refilled, walking the tunnels would be a job you could do instead of running a
shop — and since every trip makes the next one worse, the cost only works if
the reward does not come back.

## What is in the tunnels

Something lives down there. The **first trip is nearly free** — one slow thing
a bat puts down in a swing — and that is deliberate: the sewer has to be safe
enough once that you are willing to try it again.

Every trip after that is worse, and nothing resets:

| Trips | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|
| **How many** | 1 | 1 | 2 | 3 | 3 | 4 | 5 | 5 |
| **Tier** | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |

By the late tiers the bat is not enough and they are faster than you. They also
notice you from nearly twice as far when the torch is on, which is the one real
decision down there: see where you are going, or not be seen.

This is what stops the sewer being a free shortcut. Every time you use it —
to reach the far end quietly, or to escape a raid — you are raising the price
of using it again.

## Running for it

The manhole in the stockroom is a way out. Go down it while the door team is
coming through and you live — but they take the place apart behind you:
**the stash, the night's takings and your cash go with them**, and the heat
stays exactly where it was.

That price is the point. Fleeing has to cost more than fighting or the weapons
and the fittings would never be worth buying, and the raid would stop being a
threat the moment you learned where the ladder was.

## The end of the road

There is something at the far west end of the street. It is past the last
working lamp, set back in an alcove, behind a skip — you cannot see it from
the kiosk and nothing points at it. Walking into it **takes a screenshot by
itself** and writes it to `user://screenshots/`, because the whole point of
finding it is having proof you did.

It knows your name. In order of preference:

1. A name you typed into the pause menu.
2. **Your Steam persona name** — the call is written and guarded, so dropping
   GodotSteam into the project and initialising it is all that is needed, with
   no code change here. The plugin is not bundled: it is a per-platform binary
   and this repository ships none.
3. Your operating system account name.
4. `STRANGER`.

## Lighting

Two render layers, four metres apart. The world is a shop on a street with
tunnels underneath, and light does not care about the floor between them: with
shadows off — which they are everywhere, because this is a GL Compatibility
build aimed at low-end hardware — a sewer lamp was lighting the stockroom floor
above it, through solid brick.

So the tunnels render on their own layer and their lamps light only that layer.
The player's torch and muzzle flash reach both, because the player is the one
thing that crosses between them.

The street lamps were the other half. They ran at an eighteen-metre range,
reaching fourteen metres *through the shop's front wall* to light the floor
behind the counter — wrong on its own terms, and enough to put nine simultaneous
lights on the counter against the **eight-per-object limit** that GL
Compatibility enforces silently. The renderer was dropping one, and which one it
dropped could change as the camera turned, which is how you get light popping.

Lamps are now a nine-metre pool, which is about what a sodium lamp five metres
up actually throws, and suits the street better — the lamps are meant to thin
out into darkness as you walk west, and a tighter circle does more of that. The
shop's own strip lights were raised to carry the room, since they had been
quietly relying on light coming through their own walls.

| Where you stand | Lights reaching it |
|---|---|
| Behind the counter | 9 → **6** |
| At the hatch | 9 → **6** |
| The aisle | 8 → **6** |
| Stockroom | 9 → **4** |
| Far end of the road | 4 → **0** |

## Sound

There is no music file. The score is eight layers synthesised at boot — two
chord beds, two bass pulses, a plucked motif, a sour high tone, a tremolo
strain and a subterranean drone — all the same length and tempo. They play in
sync from the moment the shift starts and are never stopped while a scene is
running, so they stay in phase all night. Only their volumes ever change.

What makes it an arrangement rather than a mix is the **section**. There are
four — settled, working, wary, bad — and each names a different set of layers.
Sections move **one step at a time, on a bar line**, so the score builds and
unwinds in a musical order instead of crossfading wherever the tension happens
to land. Climbing takes more tension than staying does, so a single tense
moment does not make the music flap on a threshold.

Two things move the score that are nothing to do with tension:

- **Which night it is.** Later nights bias the whole arrangement upward, so
  night ten never opens as quietly as night one did.
- **How late it is.** As the shift wears on the pad recedes and the sub comes
  up underneath it. The small hours sound emptier and heavier.

The wary and bad sections switch the bed from Am–F–C–G to Am–F–Dm–E. That E is
a major chord in a minor key, and its G# is why the dark bed sounds like it is
leaning on you.

### Where a sound comes from

Effects that happen somewhere in the world are played **positionally** —
gunshots, a raid unit going down, a customer's footsteps, the chime when
somebody reaches the counter, and everything in the tunnels. That last one is a
gameplay system rather than polish: the sewer is pitch dark, so which direction
a thing is coming from is the only information you get about it, and hearing a
raid form up on your left is the difference between being ready and not.

Interface sounds and things happening in your own hands stay flat, because they
are not in the world.

Effects have their own bus, so they can be turned down without taking the music
with them — they used to play straight onto Master, where the only way to
quieten a gunshot was to quieten the whole game.

Two things here are easy to get wrong and are tested rather than trusted. A
still-sounding cue is never cut off while an idle voice is free, which plain
round-robin did. And the positional pool has to sit in the **same viewport as
the camera**: this game renders the world into a SubViewport, and an
`AudioStreamPlayer3D` looks for its listener in its own viewport, so a pool left
on the autoload under the root would search a viewport containing no 3D camera
at all. The symptom is silence, which is indistinguishable from a sound that was
never triggered.

**The score is not allowed to know who is police.** A sting when an officer
walks in would hand you the answer the entire game is built on withholding.
Tension is computed from three things you can already see on your own screen:
the heat meter, whether the person at the counter has made the ask, and
whether somebody walked out tonight who shouldn't have. `tension_from()` takes
no argument that could distinguish an officer from a civilian, and the smoke
suite asserts that two identical situations score identically. The night number
and the clock *are* fair game — both are on screen already.

### Headroom

Every cue is synthesised to full scale and clamped there — the gunshot measures
exactly 1.00 — so a single sound is already at the ceiling before any bus gets
hold of it. One of those is fine. A raid is not: six units firing, their rounds
landing, the score at full tilt and the rain underneath it, all inside a few
milliseconds. Nothing sums that before it reaches the output, and anything over
full scale comes back as hard digital clipping, which is a crunch rather than a
bang. The loudest moment in the game was the one that broke.

Master carries a hard limiter set to -0.5 dB. Below that ceiling it does nothing
at all, so the mix is exactly as it was written; it only ever catches the peaks
that would otherwise have wrapped. Turning the whole game down instead would
have cost the raid the impact it is supposed to have. The default master volume
of 0.8 already leaves some headroom — a player who puts it to 1.0 has none, and
this is what covers them.

## Carrying a run over

The game writes your run after every shift, and on launch the title offers to
**carry on from the night you stopped**, or to start again from the first. Dying
ends the run and clears it — there is nothing to come back to.

Worth saying plainly because it was broken for most of this project's life: the
save was being written diligently after every shift, every trip down the ladder
and every discovery, and never once read back. The loading code was complete and
correct. It simply had no caller, so every launch began at night one however far
the last run got.

The loader does not trust the file. A save is the one input to this game that
comes from outside it: it can be older than the build reading it, newer than the
build reading it, or opened in a text editor by somebody who fancied a hundred
body bags — none of which is exotic once a game is on a store and taking patches.

The sharp edge was the id lists. `weapons` goes straight into what you are
holding, and what you are holding is used as a bare key into the weapons table,
so a save naming a weapon this build no longer has took the game down the first
time you pressed the change-weapon key. That is the shape of "won't start after
the update" in a review. Every id is now checked against the table it will be
looked up in, anything unrecognised is dropped and logged, and every number is
pulled back into the range the rest of the game is written to expect. Nothing
here is a cheat check — somebody editing their own save is welcome to it — it is
only that a night should be at least one and a reputation should be a percentage.

## Learning it

There is a lot to know here, and for a game that asks you to make judgement
calls, being confused about the *controls* is the worst possible reason to lose.

So there is no tutorial and no first night on rails. Twelve hints fire **once
each, ever**, the first time the situation they explain actually arises, as a
line in the same notice column everything else uses — the first customer puts
shopping on your counter, the first person makes the ask, the first shelf runs
out, the first body hits the floor. Then they never speak again. Progress lives
in `user://hints.cfg`, so a second run is silent from the start.

The rule they are written to: **explain the control, never the decision.** Which
key sweeps somebody is a thing the game should tell you. Whether to sell to them
is the entire game and it stays yours. The smoke suite greps every hint for
advice-shaped phrasing and fails on it, so that stays true as hints get added.

`Esc` → SETTINGS turns them off, or shows them all again.

## Achievements

Ten of them, listed under `Esc` → ACHIEVEMENTS. They work with **no Steam at
all** — the game keeps its own record in `user://achievements.cfg` and the page
says which it is rather than implying a connection the build does not have.

| API name | What it wants |
|---|---|
| `FIRST_NIGHT` | Survive your first shift and make the rent |
| `FIVE_NIGHTS` / `TEN_NIGHTS` | Last that long |
| `CLEAN_READ` | A whole night without being wrong about anybody |
| `SPOTLESS` | Finish a night with your name still at 100% |
| `MADE_THE_RENT` | Pay the rent on shelf trade alone, nothing under the counter |
| `SURVIVED_RAID` | Survive a raid *without* going down the manhole |
| `NO_WITNESSES` | Deal with a body before anybody sees it |
| `TUNNEL_RAT` | Find what is at the end of the spur |
| `MASTER` | Hidden |

**Nothing unlocks for shooting people.** The rest of the game goes to
considerable trouble to charge you for that, and a trophy would undercut all of
it. The smoke suite asserts it, so it stays true.

The API names are what you type into the Steamworks partner site and are
permanent once shipped — changing one orphans everybody's unlock — so they are
deliberately dull while the display names stay free to rewrite.

## Steam

Nothing in this repository is a Steam build, and the plugin is deliberately not
bundled: GodotSteam is a per-platform binary and this project ships no binaries
it did not generate. What *is* here is every hook, written so that dropping the
plugin in and initialising it is the whole job.

| Feature | State |
|---|---|
| **Persona name** on the board at the end of the road | `PlayerIdentity.steam_name()` — falls back to the OS account name, then `STRANGER` |
| **Achievements** | `Achievements._push_to_steam()` mirrors every unlock with `setAchievement` + `storeStats` |
| **Overlay, cloud, rich presence** | Needs the SDK; nothing to do in-game |

Every call is guarded the same way: the singleton may be absent, present but
uninitialised, or present with the client not running. None of those are errors
— they are the normal case for a build running outside Steam, which is every
build this repository produces today. The suite tests the *absent* path, since
that is the one that actually runs.

What has to happen outside the code, when there is an app ID:

1. Add GodotSteam and call `Steam.steamInit()` at boot.
2. Create each achievement in **Steamworks → Stats & Achievements** using the
   exact API names above.
3. Drop `steam_appid.txt` next to the binary for local testing.
4. Point **Steam Auto-Cloud** at the save directory — no code needed. The game
   writes `kiosk_save.cfg`, `achievements.cfg` and `keybinds.cfg` to Godot's
   `user://`, which is `%APPDATA%\Godot\app_userdata\Kiosk At Midnight` on
   Windows, `~/.local/share/godot/app_userdata/Kiosk At Midnight` on Linux and
   `~/Library/Application Support/Godot/app_userdata/Kiosk At Midnight` on
   macOS.

## Controller

Fully playable on a gamepad, which matters more than it sounds: this is a
seated, slow, reading-heavy game in one small room, which is exactly what a
handheld is for. Without a pad it could not be played on a Steam Deck at all.

| | |
|---|---|
| Left stick / right stick | Walk / look |
| A · B | Use, scan, talk · Back |
| X · Y | Refill shelf · Torch |
| Triggers | Fire · Aim |
| Bumpers | Run · Sweep with the scanner |
| D-pad ↑↓ | Change hands · Reload |
| Back · Start | Notepad · Pause |

Right-stick look is squared rather than linear, so small pushes stay small —
this game asks you to settle on somebody's face and read it, and a linear stick
makes that a fight.

Dialogue and the supplier are numbered lists, and a pad has no number keys, so
it gets a cursor instead: the d-pad steps it, `A` takes the highlighted row. The
cursor only appears once a pad is actually connected — a keyboard player never
sees a selection they did not ask for.

The pad is bound **alongside** the keyboard rather than instead of it, so you
can put the controller down mid-shift and carry on. Rebinding a key leaves the
controller alone.

## Settings

`Esc` opens a pause menu that actually freezes the game, on three pages.

**Controls** rebinds every key. Bindings are stored by *physical* key, so a
QWERTZ or AZERTY keyboard already works without touching anything — rebinding
is there for people playing one-handed or left-handed, which layout does not
help with. A key already doing another job is refused rather than silently
accepted, `Esc` cannot be taken, and overrides persist to `user://keybinds.cfg`.

**Settings** opens with **display**: windowed, borderless or exclusive
fullscreen; five window sizes; vertical sync; and a frame limit from 30 up to
240 or unlimited. All of it persists, and the first launch picks the largest
listed size that actually fits the screen rather than a hardcoded 720p — so a
1440p monitor does not get a small window in the corner, and a handheld is never
handed a window it cannot fit.

Then language — shown only when there is more than English installed — volume,
music, effects, mouse sensitivity, field of view, subtitles, hints, your name
for the board at the end of the road, plus the two that matter:

- **Screen effect** — scanlines, grain, vignette and colour fringing.
- **Retro geometry** — vertex jitter and affine texture warping.

Both default to well under full strength, and that is a correction rather than
a taste. The effects are honest — the jitter and the texture swim are what the
hardware really did — but the hardware did it at 320x240 on a television across
the room. Here the 3D view is rendered at 426x240 and scaled up three times, on
a sharp panel, a foot from your face, so every artefact arrives three times the
size it was ever meant to be. At full strength the wall texture crawls the whole
time you are moving and an hour of it is genuinely unpleasant. Both sliders
still go to 1.0 for anyone who wants the real thing.

The screen effect is also applied *below* the interface rather than over it. It
sat on top for most of this project's life, which meant the channel-split that
sells a cheap composite signal was being applied to text — the title screen read
as though it needed 3D glasses, and nothing in the game was sharp. The world
goes through the whole grubby pass; the interface is drawn afterwards and stays
exactly as crisp as it was rendered.

Both go down to zero independently, and at zero the game renders clean, stable
and perspective-correct. This is an accessibility control, not a taste one:
those effects cause real eye strain for some people, and the jitter that sells
the era is motion instability by another name. Turning them off costs you
nothing but the look.

## Language

The game is written and shipped in English, and it is not stuck there.

Every string a player reads goes through `Loc.t()` — or `Loc.f()`, if it has a
number in it — and the English text *is* the key. There is no `MENU_TITLE_02`
layer to keep in step with anything, nothing to look up while writing a line,
and a translation that is missing a line falls back to the English original
rather than to a shouty identifier.

`locale/kiosk.csv` is what a translator is handed: one row per string, a `key`
column and an `en` column beside it. To add a language, add a column, name it
with the locale code, and fill it in:

```csv
key,en,de
"Torch on.","Torch on.","Licht an."
"Found %d.","Found %d.","%d gefunden."
```

Anything left blank falls back to English, so a half-finished translation is
playable rather than broken. A translation that has lost or gained a `%d` is
refused and the English is used, because these files are meant to be edited by
people and a mismatched format string would otherwise take the game down.

Tables are read at runtime with `FileAccess`, not imported as resources. Two
consequences, both deliberate: `locale/kiosk.csv.import` is pinned to `keep` and
committed (otherwise Godot turns it into a binary `.translation` and drops the
readable file from the build), and anything dropped into `user://locale/` wins
over what shipped — so somebody can install or correct a community translation
without a rebuild. A language row appears in the pause menu only once there is
more than English to choose between.

Regenerate the template after writing any new player-facing text:

```sh
godot --headless --path . tools/MakeTemplate.tscn
```

It reads the source for every `Loc.t`/`Loc.f` literal and every string handed
straight to a `UIKit` builder, then walks the content tables — the tells, the
hints, the achievements, the greetings, the shopping — as the live dictionaries
they are, so a new tell is in the template the moment it is written.

What stops the template rotting is neither of those passes. The smoke suite runs
the whole game with `Loc.recording` on and fails if it is ever asked to
translate a string the template does not contain, printing the missing lines and
writing them to `user://locale-missing.csv` in the template's own format. A gap
is a red test, not an English sentence in the middle of somebody's German.

Names, streets, employers and registration plates are not translated. They are
the setting rather than the language, and a file that reads as documentary
evidence stops doing that if the person in it is renamed. Everything that
*describes* — occupations, prior matters, what the scanner found, what the
terminal makes of it — is translated, so a German player reads a German file
about a man called Tomas Dressler on Cutter Lane.

## Controls

| | |
|---|---|
| `WASD` | move · `Shift` run · `Ctrl` crouch behind the counter |
| `E` | scan an item, work the till, take stock, talk |
| `Q` | refill the shelf you are looking at |
| `F` | sweep them with the scanner (pick it up off the counter first) |
| `TAB` | notepad — what you have on the person at the window |
| `X` | change what is in your hands |
| `1`–`5` · wheel | reach straight for a slot, or roll through them |
| `T` | torch |
| | all rebindable in the pause menu |
| `Mouse 1` | use it |
| `1`–`9` | choose a dialogue option |
| `Esc` | close a panel · pause and settings |

## Running it

Needs [Godot 4.3](https://godotengine.org/download) — no other dependencies.

```sh
godot --path .              # play
godot --editor --path .     # open in the editor
```

## Tests

```sh
godot --headless --path . res://tests/SmokeTest.tscn      # construction + wiring
godot --headless --path . res://tests/BalanceTest.tscn    # is the game fair and solvable
```

`SmokeTest` builds every system once and drives a transaction, a sale to an
officer, a shooting and a raid through it. It also **walks the sewer with shape
queries** — a shaft built as four solid walls puts a slab straight across the
tunnel and a one-piece tunnel roof caps the shaft, and both of those look
completely fine in the editor while leaving you teleported into a sealed box of
brick. That is exactly what happened, and the test now catches it. `BalanceTest` is the more
interesting one: it simulates thousands of customers and asserts that a player
who investigates properly catches most officers and rarely condemns anyone
innocent, that a player who never asks questions gets a lot of false positives,
and that the two score bands **overlap** — because if a clean read were ever
guaranteed there would be no judgement left to make.

Current figures at night 4:

```
A player who investigates properly:
   officers  min -10  median  11  mean  10.8  max  29
   civilians min  -6  median   0  mean  -0.9  max   4
   officers caught 95% · civilians wrongly flagged 7%

A player who scans and reads but never asks:
   officers caught 100% · civilians wrongly flagged 50%
```

There is also a screenshot harness, which drives the real game under a real
renderer and writes frames to disk — headless tests cannot tell you the kiosk
looks like a kiosk:

```sh
xvfb-run -a godot --path . res://tests/Screenshots.tscn -- --shots=/tmp/shots
```

### Checking that the checks bite

A suite that passes proves nothing on its own. Three of the checks in this
repository have, at one point or another, been flaky, silently skipped, or built
on a measurement that was wrong — and every one of them was green while it was
broken.

So the important invariants get verified by breaking them on purpose and
confirming the suite goes red with a message that names the actual problem.
Each of these was run, seen to fail, and reverted:

| break | what the suite said |
|---|---|
| officers made 1.2% taller than civilians | `nothing a player can see says whether they are police — leaking: height_scale (6.6 sigma)` |
| night waits on the shop emptying alone | `and the night ends rather than waiting for them forever` |
| save loader trusts its weapon list again | `the weapon that does not exist is dropped` |
| limiter taken off the master bus | `Master has a limiter on it` |
| meter sets size before minimum size | `and its fill actually moved (160 -> 160)` |

The first is the one that matters most. A 1.2% difference in height is not
something any player could see, name, or consciously use — and it is exactly the
kind of thing that would quietly make the game answer its own question. Six and
a half standard errors is the suite noticing something no human would.

The third, fourth and fifth are fixes made in this project's own history. Each
was put back to check the test written alongside it would have caught it.

## Playing it, automatically

```sh
godot --headless --path . res://tests/Soak.tscn -- --nights=5
```

Run every suite under a timeout. A parse error in a test file leaves a scriptless
node that never calls `quit()`, so the run hangs forever rather than failing —
which on CI is a stuck job rather than a red build.

The other two suites check parts in isolation and argue about numbers. Neither
can catch the failure that matters most before shipping: **a night that never
ends.** So this one drives the real game — a bot works the counter, scans,
takes payment, restocks, refuses every ask, buys stock between shifts and runs
for the manhole when the door goes — and watches for shifts that stall, clocks
that stop, and nights that serve nobody.

It also reports a **frame-time baseline** per night — mean, median, p99, worst,
and the live object count — so that optimising has something to aim at. Headless,
so it measures CPU and script cost with nothing being drawn: the right tool for
finding a script-side hotspot and the wrong one for judging fill rate. The
current shape is a healthy ~6.9ms mean with a ~8ms p99 and occasional 20-30ms
spikes at night boundaries, where the world is being rebuilt.

It is also how an optimisation gets checked rather than asserted. The HUD used
to throw its health meter away and build a new one every frame — two `ColorRect`
allocations and a two-node subtree queued for freeing, sixty times a second, to
redraw a bar that moves twice a night. Meters are now built once and moved in
place, and the p99 came down from 9.9ms to 8.0ms with the worst case down from
26ms to 21ms. The mean did not move, because at this scale the mean is the
harness's own pacing floor; the tail is the part that was real.

It found a fifth later, and this one needed the *length* of the run rather than
the fact of it. Object count was climbing by about 285 a night, dead linear
across six nights, and by night six the p99 had gone from 7.9ms to 20ms. Nodes
stayed flat the whole time and not one node was ever orphaned — so nothing was
failing to be freed, and every instinct about a missing `queue_free` was wrong.

It was the caches, which is to say it was the optimisation pass. Generated
textures, materials and meshes are keyed on what they were asked for, which is
correct right up until the thing being asked for is unique to one person: their
face, the material built from it, the eleven boxes scaled to their own height
and build. Keyed that finely, nothing is ever reused *and* nothing is ever
dropped. The cache had stopped being a cache and become a list of everyone who
had ever come to the window.

Three changes. Mesh sizes snap to five millimetres instead of a tenth of one,
because a tenth of a millimetre on a person is not a distinction anybody can see
and it meant no two customers ever shared a shape. Body proportions snap to a
grid of 272 types, for the same reason and with the same invisibility. And every
cache has a ceiling, dropping the oldest entry past it — a mesh in use is held
by the node drawing it, so eviction only costs a rebuild if that exact shape is
asked for again.

Object count now settles at about 3,690 instead of climbing past 4,576 and
going, and the night-six p99 is 7.96ms rather than 20. Memory follows: 36 MB on
the first night, flat at 38.3 MB from the fifth onward. The soak reports that
alongside the object counts, because objects settling does not prove the memory
behind them has — an image is one object however many pixels it holds.

It checks this on every run, two ways. A jump of more than ninety in one night
fails it, which catches a cache filling fast; and a total over 1,200 fails it
too, which catches one that adds twenty a night and would otherwise pass the
first check forever. The growth limit is deliberately loose — the leak was two
to three hundred a night, and set any tighter the check failed on its own
warm-up about one run in three. A flaky check is worse than no check, because it
teaches you to ignore it.

The game reports its own start-up cost in the log: **open for business in 3,163
ms** on this machine, headless. Everything is generated at launch — every
texture, every mesh, every sound, the icon — and that is the price of it.

It earned its keep immediately. Four bugs found on the first day, none of which
any unit test in this repository could have found:

- **The night could never end.** If the clock ran out while customers were
  still due to arrive, arrivals stopped below last orders and the exit
  condition needed a counter nothing would decrement again. A hard softlock,
  reachable by playing *carefully* — the clock was calibrated at roughly one
  customer per 20 seconds and anybody who actually reads the files runs slower
  than that.
- **The shift was too short for its own customer count.** That 20-second figure
  predated customers shopping the floor for themselves; a visit measures at
  130-160 seconds and only four fit in the shop at once. A third of each
  night's custom was never sent, while the rent went on scaling against the
  full count.
- **A customer with an empty basket blocked the till for 110 seconds.** With
  nothing to ring up the till never opens, so the code that moves them on never
  ran, and the only way out was a dismissal — which costs your name. Being
  punished twice for an empty shelf is a trap, not a trade-off.
- **A customer who could not get round the shop stood there all night.**
  Queueing and the counter both had patience timeouts; the shop floor had none.
  Four of them filled the shop and shut the door on everyone else.

All four have regression tests in the smoke suite that fail against the old
code.

### Timers and tweens that outlive their subject

Two things in Godot keep running after the thing that started them has gone: a
`SceneTreeTimer`, and a `Tween` bound to a node other than the one it animates.
Connect either to a lambda and the lambda captures by value, so the connection is
owned by nothing and fires into a capture that has been freed — `Lambda capture
at index 0 was freed`, dozens of times a night in the soak.

There were two of them. A customer served in the last seconds of a shift left a
two-second leave timer behind; the shopping tween that slides an item into the
bag was started on the till rather than on the item, so clearing the counter
freed the item while the tween carried on holding it. Neither did any harm — the
call is skipped — and that is the problem, because an error in the log that is
always there is an error nobody reads.

The fixes are the same shape both times: give the callable an owner. A method
callable (`_leave.bind("served")`, `_refresh_stats.unbind(1)`) is disconnected
when its object is freed, and a tween started with `node.create_tween()` dies
with the node it is moving. Neither is a workaround; both are what the engine is
built to do, and the lambda was the shortcut.

### One line that made every surface transparent

For months this game had a bug that read as: *everything disappears and comes
back depending how far away I am and which way I am looking.* Objects through
walls. Stock you cannot see on a shelf you are standing at. A table that vanishes
at one particular angle. It was diagnosed twice — once as the eight-lights-per-
object limit, once as the shader's near-plane arithmetic — and both times
something real was found and fixed and the symptom stayed exactly where it was.

The cause was line 63 of `shaders/ps1.gdshader`:

```glsl
ALPHA = c.a;
```

A spatial shader in Godot 4 becomes a **transparent** material simply by
assigning to `ALPHA`. Nothing warns you and nothing looks obviously wrong.
Transparent materials do not write to the depth buffer and are drawn after all
opaque geometry, sorted by how far each object's *origin* is from the camera.

That sort is the whole failure. This world is built out of long boxes — a hundred
metres of road, a shop wall, a counter — whose centres are metres away while
their faces are at arm's length, with small props scattered among them. Sorting
by origin gets those pairs backwards, and which way it gets them wrong changes
as the camera moves. Every surface in the game goes through this shader, so every
surface in the game was transparent.

It was writing a constant, too. Every generated texture is `FORMAT_RGB8`, every
cut swatch comes off an RGB sheet, and nothing has ever set `alpha_scissor` — so
`c.a` was 1.0 everywhere. The entire depth buffer had been given up for a value
that never varied.

Two things guard it now. `tools/DepthProof.tscn` stands a bright red box behind a
long wall under a real renderer and counts red pixels: the geometry is arranged
so that origin-sorting draws the box over the wall and depth-testing does not, so
the answer is unambiguous. And because the headless suite draws nothing and
cannot take that picture, the smoke test reads the shader source and fails if
anything assigns `ALPHA` again.

The first version of the depth proof was wrong in an instructive way. It put the
wall between the camera and the box the obvious way round — and passed, because
back-to-front sorting hides a nearer wall correctly. A test for a sorting bug has
to be built so the sort gets it wrong, or it proves nothing.

## When something goes wrong

The game writes `kiosk.log` next to the saves, and keeps the previous run's as
`kiosk.previous.log`. The previous one is the half that matters: a crash means
the player relaunches to tell you about it, and a single log file would already
have been overwritten by the time they did.

The header is what a bug report needs before the first line of gameplay — build,
OS, renderer, display server, screen size and refresh rate, CPU, memory — because
nearly every "cannot reproduce" comes down to one of those being different from
the reporter's. After that it records each night opening and closing with the
money, heat, name and rent, every raid and why it happened, fleeing, and the end
of a run.

Every write to disk goes through `Persist`, which checks the return code.
Previously all five `ConfigFile.save()` calls dropped it — fine until a disk is
full, a profile directory is read-only, Steam Cloud is mid-conflict or antivirus
has the file open, all of which fail and all of which used to fail *silently*.
Now a failed run save says so on screen while the player can still do something
about it, and everything lands in the log.

## Building for release

Install export templates for 4.3-stable first (Editor → Manage Export
Templates). Then:

```sh
godot --headless --export-release "Windows Desktop" build/windows/KioskAtMidnight.exe
godot --headless --export-release "Linux"           build/linux/KioskAtMidnight.x86_64
godot --headless --export-release "macOS"           build/macos/KioskAtMidnight.zip
```

**All three have been built and checked:**

| | |
|---|---|
| Windows | `PE32+ executable (GUI) x86-64` |
| Linux | `ELF 64-bit x86-64`, launched and played |
| macOS | `Mach-O universal binary` — x86_64 **and** arm64, so Intel and Apple Silicon |

### The icon

`icon.png`, `icon.ico` and `icon.icns` are drawn by `scripts/util/ProcIcon.gd`
and written by:

```sh
godot --headless --path . res://tools/MakeIcon.tscn
```

They are the only generated files that are **committed** rather than made at
runtime, because the exporters need them to exist before the build starts —
Godot copies the `.icns` into the `.app` bundle and hands the `.ico` to rcedit.
The generator stays the source of truth, and the smoke suite fails if the
committed files no longer match what it produces.

It is one drawing described in normalised coordinates and rasterised at
whatever size is asked for, so the 16px taskbar icon and the 1024px store art
are the same picture rather than two things that have to be kept in step. The
smoke suite checks at every size that the hatch is still clearly brighter than
the night around it, which is the one thing that has to survive being sixteen
pixels across.

The **window** icon is not loaded from any of those files — `Game.gd` draws a
64px one at startup and hands it to the display server, so the running game
carries its icon on every platform that has window icons at all, from the same
generator as the files on disk.

macOS gets its icon in the bundle automatically. Writing one into the Windows
`.exe` header additionally needs the external `rcedit` tool, which is not wired
up here — `application/modify_resources` is off in the preset. Turn it back on
once you have rcedit configured; the `.ico` is already generated and the preset
already points at it. Until then the Windows *window* has the icon but the file
in Explorer does not.

### Alt-tab

Losing window focus during a shift or a raid opens the pause menu, which stops
the tree and gives the mouse pointer back. This is not a nicety for a
first-person game that captures the cursor: without it somebody answers a
message mid-raid and comes back to a dead shopkeeper, with the pointer still
grabbed while they are trying to click on something else.

It does not un-pause itself when focus returns. Deciding when you are back in
the room is yours to make, and a game that resumes the instant its window lights
up drops you straight into whatever you tabbed away from.

### Verifying a build you can't watch

Release binaries ship with a `--selftest` flag. It opens the kiosk through the
real title screen, plays a few seconds, writes a frame to disk and exits 0:

```sh
./build/linux/KioskAtMidnight.x86_64 --selftest=/tmp/shot.png
# [selftest] wrote /tmp/shot.png (1280x720)
# [selftest] night 1 · money 85 · in shop 4 · in line 1 · at the till: yes
# [selftest] score section 1 · playing: bed, pulse
# [selftest] build 0.9.0
# [selftest] language en · 798 in the table · offered: en
```

It also writes the world buffer on its own, next to the composited frame, as
`<name>.world.png`. When a picture looks wrong that is what says whether it was
never drawn or only badly put together.

The last two lines are there because a rendered frame cannot vouch for
everything. The score reports which section the arrangement reached and what is
audible; the translation table is a loose file rather than an imported resource,
so reading it back out of the packed build is the only proof it survived the
export.

This exists because "it didn't crash" proves very little, and a headless test
cannot tell you the exported build renders at all. It is how the table above
was confirmed.

### Building from a fresh clone

Verified rather than assumed, because it is the thing that breaks quietly:
cloning the repository and running one export command produces a working game.
No editor pass first, no import step, nothing to set up.

```sh
git clone <repo> kiosk && cd kiosk
godot --headless --export-release "Linux" out/Kiosk.x86_64
```

`*.import` is gitignored, so a fresh clone has no import metadata for `icon.png`
— the exporter reimports it on the way past and packs the result. Two things
that show up in that log and are both harmless: `reimport: step 1: icon.png` is
that happening, and `SHADER ERROR: Global uniform 'ps1_snap' does not exist` is
the export's own shader compile running before project settings register the
globals. The shipped binary has them and renders correctly; the check for that
is `--selftest` on the result, which is how this paragraph was written.

### An open question: dark frames under software GL

Worth writing down because it is unresolved rather than because it is solved.

Rendering the shipped Linux binary under Xvfb with llvmpipe, the world buffer
sometimes comes back at about a quarter of its normal brightness — mean 13
against a usual 45 — with the counter, the customer and the floor present and
the walls, ceiling and shelves unlit. How often depends on the window:

| window | logical space | 3D buffer | runs | dark |
|---|---|---|---|---|
| 1280x720 | 1280x720 | 426x240 | 16 | 0 |
| 1280x800 | 1280x720 | 426x240 | 3 | 0 |
| 1280x720 on a 2560x1080 screen | 1280x720 | 426x240 | 2 | 0 |
| 1920x1080 | 1280x720 | 426x240 | 10 | 3 |
| 2560x1080 | 1706x720 | 568x240 | 8 | 8 |

The middle two columns are why this took so long to read. The interface is laid
out in a fixed 1280x720 space that is scaled to the window, so a 1920x1080
window has exactly the same logical size and exactly the same 3D buffer as a
720p one — those rows are the same test at two window sizes, and one of them
fails sometimes. Only the ultrawide row is a different shape, and it fails every
time. It is not the aspect ratio: 16:10 behaves like 16:9. It is not the screen:
a small window on a large screen is fine.

The 2560 case returns a mean of 13.5 to within a tenth across every run, which
is not what a randomly flickering strip light would produce — whatever it is, it
is deterministic.

Things tried that did not explain it: the CRT pass (curvature is off, and the
buffer is captured before the pass anyway); the camera (identical position,
facing and field of view in the lit and dark frames); waiting four complete
frames before reading, in case the capture was racing the renderer; and raising
the per-object light budget, which made every frame black because that shader
will not compile at 32 lights on this driver.

Most likely llvmpipe, which is a software rasteriser and not representative of a
real GPU. Possibly something in GL Compatibility that a player on an ultrawide
would also see. This environment cannot tell the two apart — settling it needs
one run on real hardware at 2560x1080 or wider, and that is the first thing to
do before a store page goes up.

Two corrections went into that table, both worth more than the finding. It was
first read as an aspect-ratio bug, on two ultrawide captures and no controls;
three runs at 1920x1080 came back lit and killed it. And the brightness numbers
behind it were produced by a script that assumed three bytes to a pixel against
a four-byte image, which reported a perfectly lit frame as almost black. The
classification survived re-measurement — the two clusters were real and well
separated — but nothing about that was luck. `--selftest` now reports the mean
itself, read through the engine that wrote the image, so there is no format
guess between the build and the number.

## Assets

### Painted textures

Surfaces come from a hand-made pack where there is one for them, and from code
where there is not. `textures/` holds the swatches the game loads; each is
matched to a surface by name in `World._surface()`, which asks for the painted
one and falls back to the generator if it is missing. A half-finished pack is a
game with some painted walls, not a broken one.

The pack arrived as presentation sheets — one large image per theme, each
showing a grid of labelled swatches with albedo, normal and roughness side by
side. Made to be looked at rather than loaded, so `tools/CutTextures.tscn` takes
the albedo panel out of each swatch and writes it as something the game can put
on a surface:

```sh
godot --headless --path . tools/CutTextures.tscn
```

Four things it does that are worth knowing. It trims the border the sheet draws
around every swatch by finding it rather than assuming it, so a crop rectangle
estimated by eye self-corrects. It removes the caption printed above each swatch
— every one of them has its pixel size written a few pixels clear of the picture,
and a crop that catches it gets mirrored into all four corners, which is how the
shop floor came to be tiled six times across with the words 512x512 written on
it. It backs off the normal map that sits to the right of every albedo, found by
its colour — tangent-space blue is a signature nothing real has — because a crop
estimated by eye lands wide about half the time and a strip of that baked into a
wall is unmistakable. And it mirrors each cut into a tile, because a swatch off a
contact sheet does not tile and a wall that does not tile shows a seam every few
metres. Mirroring is crude next to a proper heal, and it is the right crude: it
cannot produce a seam, it keeps the grain and colour exactly, and at this
resolution in this light the symmetry does not read.

The caption test and the border test are deliberately different questions. A
border is dark and flat; a caption is dark with something *white* in it. That
distinction is what keeps either of them off the photographs — the darkest
surfaces in the pack, the sewer walls and a stack of tyres, are dark all the way
across and never contain a pixel anywhere near white.

Normal and roughness maps are ignored on purpose. The world is lit per vertex
with roughness pinned at 1.0, which is a large part of why it looks like the era
it is pretending to; a normal map would need per-pixel lighting and would undo
that.

`textures/*.png.import` is committed and pinned to `keep`, for the same reason
the locale CSV is. Left alone, Godot compiles each PNG to a `.ctex` and the raw
file never reaches the build — and because the code falls back to the generator
when a file is missing, the exported game came out looking exactly as it had
before the pack existed, with nothing failing and nothing to see. The log says
which it is: `textures: 142 painted surfaces found`.

Two sheets look like reference and are not, quite. The lighting and post-process
sheet is mostly renders of what the engine ought to produce, which the engine has
to produce for itself — but four things on it are real textures: the night sky,
the warning signs, a caged bulkhead lamp and a monitor with something on it. The
sky is the one that changed the game. The street had no lid, so looking up gave
you the environment's clear colour and the whole place read as a room with no
ceiling; one panel of cloud above the roof line is the difference between that
and being outside at night.

The decal sheet is built for a decal projector, which this game does not have and
does not need to use half of the sheet. Corroded metal is just metal, and the
large pieces — the tags, the flyposted bills — go on a panel standing a
centimetre off a wall, which is what a decal looks like from any distance you
would ever see one from. The blood is left where it is. It is the best art on the
sheet and there is nowhere honest to put it: a handprint painted into the world
is on the wall of a shop on night one, before anything has happened, telling the
player a story that is not theirs.

Cutting a texture is only half of it. For a long time this pack was a hundred
swatches on disk, loaded at launch and drawn nowhere, while the bin in the street
wore a photograph of a drainpipe — the world named about twenty of them and the
rest were dead weight in memory. If a cut is not in `World._build_materials()`
under a name something actually asks for, it may as well not exist.

That is a test now rather than a habit. `ProcTex` records every name anyone asks
for, and the smoke suite fails if a swatch on disk was never reached for — naming
the ones that were not, because the whole failure mode is that nothing goes
wrong. Two families need help from the test to be counted: a weapon only asks for
its picture when it is in your hands, and the sky comes in two and one of them is
only over the street a third of the time. The remedy for a failure is either to
wire the swatch up or to take it out of `CUTS`; both are decisions, and neither
should be made by forgetting. Twenty came out that way — swatches superseded by
better crops off another sheet, weapons the game does not have, a fluorescent
tube that came out black — and the cutter now deletes anything in `textures/`
that the current `CUTS` did not write, so a name removed from the list leaves the
disk with it.

Loading is lazy for the same reason. Decoding the whole directory at launch put
every swatch anybody had ever cut into memory for the run whether the world drew
it or not; only the names are read up front now. The log line survives, because
it is still the only thing that distinguishes "the pack is here" from "the
exporter compiled every PNG into a `.ctex` and dropped the readable files".

A cut can also land on the wrong thing. The crop rectangles are read off the
sheets by eye, and two of them came back holding the object next door — a chain
where the police baton should have been, a camera where the notebook should have
been. Both were dropped rather than shipped, and the montage step that caught
them is worth keeping in the loop: cut, look at what came out, then wire it up.

### Everything else

**Nothing else in this game was downloaded or bought.** No stock textures, no sample
packs, no model libraries, no fonts. Everything is drawn or synthesised by code
in this repository:

- **Textures** — `scripts/util/ProcTex.gd` paints brick, asphalt, lino,
  corrugated steel, product boxes and faces into small images. Faces are
  deterministic per seed, so the person at the counter and the photograph in
  their registry file are the same person.
- **Geometry** — `scripts/util/ProcMesh.gd` assembles everything from boxes and
  cylinders, including the figures, which have named limb pivots for the walk
  cycle.
- **Audio** — `scripts/autoload/Audio.gd` synthesises all 18 cues as raw PCM at
  boot: gunshots, the till, the scanner warble, and an eight-second ambient
  drone that loops seamlessly.
- **Music** — `scripts/autoload/Music.gd` synthesises eight layers at boot and
  arranges them live. See [Sound](#sound).
- **The icon** — `scripts/util/ProcIcon.gd`, one drawing rasterised at every
  size each platform asks for.

All of it is generated at runtime except the icon, which is committed as
`icon.png` / `.ico` / `.icns` because the exporters need those files to exist
before a build starts. That is the only binary in the repository, it is
generated by `tools/MakeIcon.tscn`, and the smoke suite fails if it drifts from
its generator.

This keeps the licensing position trivially clean and the repository under two
megabytes.

## How it looks

Two artefacts define the era, and both are done honestly rather than faked in
post (`shaders/ps1.gdshader`):

- **Vertex snapping.** The original hardware had no floating point in its
  geometry unit, so positions landed on a coarse grid and polygons jittered.
- **Affine texture mapping.** It had no per-pixel perspective divide, so
  textures swam across large surfaces. Feeding the rasteriser `UV * w` and `w`
  as separate varyings and dividing them back in the fragment stage cancels the
  hardware's perspective correction exactly, which is the real thing rather
  than an approximation of it.

The 3D view renders into a SubViewport at a third of window resolution and is
scaled back up with nearest-neighbour filtering. **The interface is drawn
afterwards at full resolution** — this game asks you to read registry files,
and pixelating them would be style at the direct expense of playability.

## A quirk worth knowing

Exporting or importing headlessly prints:

```
SHADER ERROR: Global uniform 'ps1_snap' does not exist.
ERROR: Shader compilation failed.
```

**This is harmless and the export still succeeds** (exit code 0, artefacts
written). Godot's headless mode uses a dummy renderer that does not implement
global shader parameters, and the retro sliders are driven by two of them.
Under a real GL context there are no shader errors at all — verified by
running the shipped binary and grepping for them. Don't chase it.

## Layout

```
scenes/Boot.tscn            entry point; everything else is built in code
scripts/
  Game.gd                   phase machine, panel routing, the SubViewport
  autoload/                 GameState · Signals · Audio · Music · InputSetup ·
                            Settings · Achievements · Tutor
  systems/
    Tells.gd                the evidence database — every tell, question, answer
    Checkout.gd             scanning, bagging, the till
    SewerDirector.gd        what is waiting down there, and how much of it
    ProfileGenerator.gd     builds the people who walk in
    CustomerProfile.gd      one person and everything knowable about them
    NightDirector.gd        the clock and the queue
    RaidDirector.gd         the door team, and how the pairs work
    BodyDirector.gd         what is on the floor, and who has seen it
  actors/                   Player · Customer · RaidUnit · SewerDweller · Body
  world/
    World.gd                shop floor, stockroom, materials, anchors
    StreetBuilder.gd        the road, the far end, the thing in the alcove
    SewerBuilder.gd         shafts and tunnels, cut into each other properly
    EasterEgg.gd            the board, and the screenshot it takes
  ui/                       HUD · terminal · dialogue · notepad · supplier · pause · reports
  util/                     ProcTex · ProcMesh · ProcIcon · PlayerIdentity
shaders/                    ps1.gdshader · crt.gdshader
tools/                      MakeIcon — writes icon.png/.ico/.icns
tests/                      smoke · balance · soak · screenshots
```

## Where it stands

This is a **playable vertical slice**: one complete night loop, escalating, with
the raid, the economy and the detective system all live and tuned.

Known gaps, in rough priority order:

- **Content depth.** Forty-three tells and nine standing questions carries a
  long way, but a determined player will eventually start recognising them.
  This is still the main thing between the slice and a release.
- **Steam is hooks, not a build.** Achievements and the persona name are wired
  and tested against the no-Steam path, but nothing here has been run against a
  real app ID, and there is no overlay or cloud configuration.
- **The Windows `.exe` has no embedded icon.** The file is generated and the
  preset points at it, but stamping it into the header needs `rcedit`.
