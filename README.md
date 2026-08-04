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
lamps thin out as you go west until there are none. Underneath it all is a run
of brick sewer from the stockroom to a ladder that comes up in the dark corner
at the far end.

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
                                          |
                                   ladder up, far end of the street
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

## The raid

When the shutter fails they throw something through the hatch, and there is a
beat of white before the first man follows it. They come through **in pairs**,
not as one crowd — eight people arriving simultaneously in a room four metres
wide is not a firefight, it is a cutscene where you lose.

They shoot at where they last *saw* you, not where you are. Crouching behind
the counter genuinely breaks their line, and there is a beat between them
acquiring you and pulling the trigger, so stepping into a doorway is a
mistake rather than an execution. The room's geometry is the weapon.

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
their patience too — leave a queue standing and people walk out with their
shopping still in their hands.

## The checkout

The reason this is worth doing by hand rather than by pressing "sell": you have
to keep your eye on the counter while you are also deciding whether the person
across it is police. The till display shows `scanned / total` and the running
price, and the till will not open until those match.

Nothing stops you skipping an item. It just means you handed it over for free.

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

## Settings

`Esc` opens a pause menu that actually freezes the game, on two pages.

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

Writing branded metadata and an icon into the Windows `.exe` header needs the
external `rcedit` tool, which is not wired up here — `application/modify_resources`
is off in the preset. Turn it back on once you have rcedit configured.

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

**There are no imported assets in this repository.** No `.png`, no `.wav`, no
`.glb`, no fonts — nothing binary at all. Everything is generated at runtime:

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

This keeps the licensing position trivially clean and the repository under a
megabyte.

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
  autoload/                 GameState · Signals · Audio · Music · InputSetup · Settings
  systems/
    Tells.gd                the evidence database — every tell, question, answer
    Checkout.gd             scanning, bagging, the till
    SewerDirector.gd        what is waiting down there, and how much of it
    ProfileGenerator.gd     builds the people who walk in
    CustomerProfile.gd      one person and everything knowable about them
    NightDirector.gd        the clock and the queue
    RaidDirector.gd         the door team
  actors/                   Player · Customer · RaidUnit · SewerDweller
  world/
    World.gd                shop floor, stockroom, materials, anchors
    StreetBuilder.gd        the road, the far end, the thing in the alcove
    SewerBuilder.gd         shafts and tunnels, cut into each other properly
    EasterEgg.gd            the board, and the screenshot it takes
  ui/                       HUD · terminal · dialogue · notepad · supplier · pause · reports
  util/                     ProcTex · ProcMesh · PlayerIdentity
shaders/                    ps1.gdshader · crt.gdshader
tests/                      smoke · balance · screenshots
```

## Where it stands

This is a **playable vertical slice**: one complete night loop, escalating, with
the raid, the economy and the detective system all live and tuned.

Known gaps, in rough priority order:

- **Nobody pushes in.** People shift their weight, glance about and complain
  as the wait drags, but the order of the queue never changes once it is set.
- **The sewer has one route.** It is a corridor between two ladders rather than
  a network.
- **The raid still has no flanking or squad coordination.** It has pacing and
  line-of-sight now, but they do not work as a team.
- **The body-bag mechanic is vestigial.** Bags auto-consume to reduce heat
  rather than being something you actually do.
- **Content depth.** Twenty-eight tells and five standing questions carries
  noticeably longer than the first pass did, but a determined player will still
  start recognising them. This is the main thing between the slice and a
  release.
- **No icon.** Ships with Godot's default, on every platform.
