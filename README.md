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

**The score is not allowed to know who is police.** A sting when an officer
walks in would hand you the answer the entire game is built on withholding.
Tension is computed from three things you can already see on your own screen:
the heat meter, whether the person at the counter has made the ask, and
whether somebody walked out tonight who shouldn't have. `tension_from()` takes
no argument that could distinguish an officer from a civilian, and the smoke
suite asserts that two identical situations score identically. The night number
and the clock *are* fair game — both are on screen already.

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

## Settings

`Esc` opens a pause menu that actually freezes the game, on three pages.

**Controls** rebinds every key. Bindings are stored by *physical* key, so a
QWERTZ or AZERTY keyboard already works without touching anything — rebinding
is there for people playing one-handed or left-handed, which layout does not
help with. A key already doing another job is refused rather than silently
accepted, `Esc` cannot be taken, and overrides persist to `user://keybinds.cfg`.

**Settings** has volume, music, mouse sensitivity, field of view, subtitles,
your name for the board at the end of the road, plus the two that matter:

- **Screen effect** — scanlines, grain, vignette and colour fringing.
- **Retro geometry** — vertex jitter and affine texture warping.

Both go down to zero independently, and at zero the game renders clean, stable
and perspective-correct. This is an accessibility control, not a taste one:
those effects cause real eye strain for some people, and the jitter that sells
the era is motion instability by another name. Turning them off costs you
nothing but the look.

## Controls

| | |
|---|---|
| `WASD` | move · `Shift` run · `Ctrl` crouch behind the counter |
| `E` | scan an item, work the till, take stock, talk |
| `Q` | refill the shelf you are looking at |
| `F` | sweep them with the scanner (pick it up off the counter first) |
| `TAB` | notepad — what you have on the person at the window |
| `X` | change what is in your hands |
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

## Playing it, automatically

```sh
godot --headless --path . res://tests/Soak.tscn -- --nights=5
```

The other two suites check parts in isolation and argue about numbers. Neither
can catch the failure that matters most before shipping: **a night that never
ends.** So this one drives the real game — a bot works the counter, scans,
takes payment, restocks, refuses every ask, buys stock between shifts and runs
for the manhole when the door goes — and watches for shifts that stall, clocks
that stop, and nights that serve nobody.

It earned its keep immediately. Four bugs, none of which any unit test in this
repository could have found:

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

### Verifying a build you can't watch

Release binaries ship with a `--selftest` flag. It opens the kiosk through the
real title screen, plays a few seconds, writes a frame to disk and exits 0:

```sh
./build/linux/KioskAtMidnight.x86_64 --selftest=/tmp/shot.png
# [selftest] wrote /tmp/shot.png (1280x720)
# [selftest] night 1 · money 85 · in shop 4 · in line 1 · at the till: yes
```

This exists because "it didn't crash" proves very little, and a headless test
cannot tell you the exported build renders at all. It is how the table above
was confirmed.

## Assets

**Nothing in this game was downloaded or bought.** No stock textures, no sample
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
