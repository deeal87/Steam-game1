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

## The loop

One night is one shift, 23:00 to 05:00.

1. **Trade.** People come to the hatch and ask for things off the shelf. Fetch
   them, hand them over, take the money. Restock when a run empties. Shelf
   trade alone never quite covers the rent.
2. **The ask.** Roughly a third of customers — and *every* undercover officer —
   will also ask for what is under the counter. This is where the money is.
3. **Decide.** Sweep them with the scanner. Pull their file on the terminal.
   Watch how they stand. Ask questions, and check the answers against the file.
   Then sell, refuse, send them away, or shoot them.
4. **Consequences.** Kill an officer and the round is yours. Let one walk and a
   door team comes back between shifts — a hard one if they left with a buy, a
   lighter one if they left empty-handed. Shoot a civilian and you get the raid
   *and* the heat.
5. **Survive the raid**, pay the rent, and the next night is worse.

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

## Controls

| | |
|---|---|
| `WASD` | move · `Shift` run · `Ctrl` crouch behind the counter |
| `E` | use, take, hand over, talk |
| `Q` | refill the shelf you are looking at |
| `F` | sweep them with the scanner (pick it up off the counter first) |
| `TAB` | notepad — what you have on the person at the window |
| `X` | change what is in your hands |
| `Mouse 1` | use it |
| `1`–`9` | choose a dialogue option |
| `Esc` | close a panel / free the cursor |

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
officer, a shooting and a raid through it. `BalanceTest` is the more
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
# [selftest] night 1 · money 85 · customer at window: yes
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

## Layout

```
scenes/Boot.tscn            entry point; everything else is built in code
scripts/
  Game.gd                   phase machine, panel routing, the SubViewport
  autoload/                 GameState · Signals · Audio · InputSetup
  systems/
    Tells.gd                the evidence database — every tell, question, answer
    ProfileGenerator.gd     builds the people who walk in
    CustomerProfile.gd      one person and everything knowable about them
    NightDirector.gd        the clock and the queue
    RaidDirector.gd         the door team
  actors/                   Player · Customer · RaidUnit
  world/World.gd            kiosk and street geometry
  ui/                       HUD · terminal · dialogue · notepad · supplier · reports
  util/                     ProcTex · ProcMesh
shaders/                    ps1.gdshader · crt.gdshader
tests/                      smoke · balance · screenshots
```

## Where it stands

This is a **playable vertical slice**: one complete night loop, escalating, with
the raid, the economy and the detective system all live and tuned.

Known gaps, in rough priority order:

- **The raid is thin.** Units advance and shoot; there is no flanking, no
  suppression, no stacking on the door. The three defences (barricade, bars,
  trap) work but are blunt.
- **No music, and audio is minimal.** Everything is synthesised, which sounds
  appropriately cheap but is not the same as sound design.
- **No settings menu.** No key rebinding, no volume sliders, no resolution
  options — all of which Steam players will expect.
- **The body-bag mechanic is vestigial.** Bags auto-consume to reduce heat
  rather than being something you actually do.
- **Content depth.** Twenty-eight tells and five standing questions carries
  noticeably longer than the first pass did, but a determined player will still
  start recognising them. This is the main thing between the slice and a
  release.
- **No icon.** Ships with Godot's default, on every platform.
