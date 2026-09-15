# Ladle

An iPhone app for the recipes in the box. Scan the handwritten cards, save
pages from Safari, write down the ones that live in your head, and cook from
all of them in one clean layout without touching the phone.

On the App Store as "Ladle: The Cooking Book" (plain "Ladle" was taken). To rename it,
change `APP_NAME` and `BUNDLE_ID` in `tools/make_project.py`, the display
names in both `Info.plist` files, the App Group id in `Ladle.entitlements`,
`LadleShare.entitlements`, `Import/Inbox.swift` and `ShareViewController.swift`,
and the two folder names. Everything else reads from those.

---

## What it does

**Scan.** Apple's document camera finds the card, flattens it, and takes as
many pages as there are. Text is recognised on the phone (Vision, accurate
mode, handwriting included), put back into reading order with two-column
cards handled, then parsed into title, ingredients, method, servings, times.
Every line the parser doubted is marked on the review screen; the scan itself
is kept with the recipe as the original.

**Import from the web.** Share a page from Safari to Ladle, or paste a link.
The importer reads the page's schema.org Recipe data (what nearly every
recipe site publishes for search engines), falls back to microdata, and as a
last resort runs the page's visible text through the same parser the scanner
uses. The photo, times, yield, tags and nutrition come along when present.

**One format.** Every ingredient line is parsed into amount, unit, name and
preparation, with the original text kept. So every recipe scales to any
number of servings, shows in cups or grams at a tap, and can be matched
against the pantry.

**Pantry.** Type in what is in the kitchen. A catalogue of about 330
ingredients with their other names (scallions are green onions, AP flour is
flour) and their aisle does the matching, and a table of about 250
substitutions knows that buttermilk is milk plus lemon juice, that panko can
be crushed crackers, that a pie crust can be made from flour and butter.
Tonight shows what is ready, what is one or two things short, and what to
swap.

**Cook mode.** One step per screen, large type, the ingredients that step
mentions underneath with their scaled amounts, the timers it mentions as
buttons. Tap the right of the screen for the next step, the left for back.
Turn on voice and say "next", "back", "repeat", "start timer", "set a timer
for ten minutes", "how much flour", "ingredients", "I'm done". Turn on read
aloud and it speaks each step. Siri does the same from across the room. The
screen stays awake.

**Timers.** As many as needed, each a local notification so it rings from the
lock screen. Pause, add a minute, stop.

**Shopping list.** Tap Shop on a recipe and only what the pantry lacks goes
on the list, grouped by aisle, quantities merged when two recipes want the
same thing. Add by hand, tick off in the store, move the checked things
into the pantry in one tap. Send as text, or into Reminders.

**Plan.** Two weeks of days, a line per meal, recipes or a note. Shop for
the next seven days in one tap.

**Log.** "Made it" with stars and a note, so the book learns which ones
get made and what changed last time.

**Share.** A recipe as text, as a card image for a text message, as a PDF for
printing, or as a `.ladle` file with the photo inside that opens in Ladle on
another phone. The whole cookbook exports the same way, as one file, for
AirDrop or a backup.

No account, no server, no analytics. The only network request is fetching a
page you asked for.

---

## Getting it on a phone

You need a Mac with **Xcode 16 or newer** and the paid developer account
(the App Group and TestFlight both need it).

```
cd kitchen
./tools/install.sh        # phone plugged in: builds, installs, launches
```

or open `kitchen/Ladle.xcodeproj`, pick the team under Signing & Capabilities
for **both** targets, choose your iPhone and press ⌘R.

`Ladle.xcodeproj` is generated, not hand-maintained:

```
python3 tools/make_project.py    # rebuild after adding or moving files
python3 tools/verify_project.py  # check every reference resolves
python3 tools/check_swift.py     # offline consistency checks on the sources
python3 tools/make_icon.py       # redraw the app icon
```

### One-time setup in the developer portal

1. **Identifiers › App Groups › +**: `group.dev.brettboggs.ladle`.
2. **Identifiers › App IDs › +**: `dev.brettboggs.ladle`, with App Groups
   ticked and that group selected.
3. **Identifiers › App IDs › +**: `dev.brettboggs.ladle.share`, same.
4. **App Store Connect › Apps › +**: name Ladle (or whatever it becomes),
   bundle id `dev.brettboggs.ladle`, SKU `ladle`.

The seven GitHub secrets from Slumbio are reused as they are; nothing new is
needed. `.github/workflows/testflight-ladle.yml` archives and uploads on every
push to `main` that touches `kitchen/`. A second workflow,
`ladle-check.yml`, compiles the app for the simulator on every push to any
branch, with no signing and no secrets, so a broken build never reaches
`main` and no Mac is needed to find out.

### Before the first submission

- Support URL `https://brettboggs.dev/ladle/`, privacy URL
  `https://brettboggs.dev/ladle/privacy/`. Both pages are live.
- App Privacy answers: **Data Not Collected**.
- Screenshots: 6.9" and 6.5" iPhone, plus 13" iPad since the app runs there.
- Review notes worth including: the share extension needs a recipe URL to
  show anything; voice control needs the microphone and speech permissions,
  which the app asks for the first time the microphone button is tapped.

---

## Project layout

```
kitchen/
├── Ladle/
│   ├── Model/     recipe, quantities, ingredient parser, catalogue, substitutions,
│   │              matcher, pantry, shopping, plan, library store, persistence,
│   │              transfer formats
│   ├── Import/    OCR, document camera, text parser, web importer, HTML, inbox
│   ├── Cook/      cook session, voice control, speaker, timers, audio session
│   ├── Intents/   Siri and Shortcuts
│   ├── Views/     SwiftUI
│   ├── Support/   theme, haptics, formatters, shake
│   └── Ladle.entitlements    the App Group, and nothing else
├── LadleShare/     the share extension: takes a URL, drops it in the inbox
├── Signing.xcconfig         includes the gitignored Local.xcconfig
└── tools/                   project generator, verifier, installer, icon
```

## Things worth knowing

**The two targets are separate modules.** `LadleShare` cannot see anything
in `Ladle/`, on purpose: it holds its own fifteen lines for writing the inbox.
`check_swift.py` fails if that changes.

**Persistence is flat JSON.** `Application Support/Ladle/*.json` plus a
`Photos/` folder of JPEGs. Every model type decodes with defaults for missing
fields, so a newer file opens in an older build and the other way round.

**Speech recognition restarts itself.** Apple ends a recognition task after
about a minute. `VoiceControl` starts a fresh one every 50 seconds and
whenever one finishes, keeping the audio engine running throughout. While
the phone is speaking a step, what the microphone hears is ignored.

**The parser is heuristic and says so.** Scanned recipes come through a
review screen with doubtful lines marked; nothing is saved without a human
looking. Web recipes with structured data skip the marks but still land on
the same screen.

**Voice is optional and off by default.** The tap zones and the buttons do
the same job. Voice is one switch in Settings for the day it stops being
scary.
