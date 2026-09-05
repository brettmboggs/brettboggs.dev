# Hush

An iPhone sleep-sound app. Every sound is synthesized in real time, a sample at
a time. There are no audio files in the bundle, nothing to download, and nothing
that loops.

---

## Getting it running

You need a Mac with **Xcode 16 or newer** and an Apple ID.

```
open app/Hush.xcodeproj
```

Then, once:

1. Select the **Hush** target → **Signing & Capabilities**.
2. Set **Team** to your Apple ID. Do the same for the **HushWidgets** target.
3. Pick your iPhone (or a simulator) and press ⌘R.

The bundle identifiers are `dev.brettboggs.hush` and
`dev.brettboggs.hush.widgets`, with an App Group of
`group.dev.brettboggs.hush`. If Xcode says an identifier is taken, change all
three consistently: the two `PRODUCT_BUNDLE_IDENTIFIER` values in
`tools/make_project.py`, and `SharedStore.appGroupID` in
`Shared/SharedState.swift` plus the two `.entitlements` files. Then re-run
`python3 tools/make_project.py`.

> Sound will not come out of the simulator's speaker in the way it does on
> hardware, and the audio session, Live Activity and lock-screen behaviour are
> only worth judging on a real phone.

### TestFlight

TestFlight needs a paid **Apple Developer Program** membership ($99/year). A
free Apple ID will build and run on your own device for 7 days at a time, which
is enough to live with the app before deciding.

With a paid account:

1. Create the app record in App Store Connect using the bundle ID above.
2. In Xcode: **Product → Archive**, then **Distribute App → TestFlight**.
3. `ITSAppUsesNonExemptEncryption` is already set to `false` in `Info.plist`, so
   you will not be asked the export-compliance question on every build.

---

## What it does

**Playback.** Background and screen-locked playback, mixing up to eight layers
with independent levels, a fade-in on start, a sleep timer with a long fade-out,
Lock Screen and Control Center transport, AirPlay, and Now Playing metadata that
shows a real countdown while the sleep timer runs. Skip forward and back move
through saved mixes, since there are no tracks to skip.

**Shaping.** Every texture has two continuous controls beyond level: the labels
change per sound (Glass/Drops for light rain, Metal/Drips for a tin roof,
Coals/Crackle for a fire). This is the thing a library of recorded loops cannot
do, and it is worth putting in front of people.

**Wake.** An alarm with a sunrise ramp: over your chosen window the mix crosses
to a gentler wake sound and climbs from silence to full, so the alarm arrives at
the end of something rather than out of nothing. Snooze, repeat days, and a
wind-down schedule that starts playback at bedtime.

**Widgets.** Home Screen and Lock Screen widgets with a working play/pause
button, a Control Center toggle, a Live Activity with a Dynamic Island countdown
while the sleep timer runs, and Siri phrases ("Start Hush", "Stop Hush", "Set a
sleep timer in Hush").

**Bedside.** A full-screen clock that drops the display to 2% brightness, keeps
it awake, and hides every control until you touch the screen.

**Journal.** Sessions over two minutes are logged locally. Streak, average, and
usual mix. No permissions, nothing leaves the phone.

---

## How the sound works

```
Renderer (audio thread)
 ├─ 17 VoiceSlots, one per catalog sound, all allocated at launch
 │   └─ Texture subclass  →  stereo frame, sample by sample
 ├─ per-voice gain ramp
 ├─ master ramp   (fade in / sleep timer / sunrise)
 ├─ tilt shelves  (one global warm↔bright control)
 └─ soft clipper
```

Two decisions drive everything else:

**Every sound is pre-allocated.** All 17 textures exist from launch, whether or
not they are in the mix. Turning a sound on is a gain change, so nothing is
allocated, attached or detached while audio is running, and nothing can click.
The cost is about 30 KB of filter state.

**Nothing blocks the audio thread.** Parameters are plain `Float` fields written
from the main thread and read on the audio thread, then smoothed or ramped
before they reach the signal. No locks, no allocation, no weak references. A
missed update costs one block, about 10 ms, and is inaudible. The contract is
written out on `Renderer`.

Textures are built from primitives in `Audio/DSP.swift`: xorshift noise, a pink
filter, a leaky integrator for brown, RBJ biquads, band-limited random walks for
gusts and swell, and a fixed-capacity grain bank for raindrops, fire crackle,
cricket chirps and rail clatter.

### Adding a sound

Two steps, and the folder layout means the project file does not need editing.

1. Add a `SoundKind` to `SoundCatalog.all` in `Shared/SoundCatalog.swift`. The
   `id` is the key the engine switches on. `toneLabel` and `motionLabel` are
   what the two shaping sliders will be called for this sound.

2. Add a `Texture` subclass in `Audio/Textures.swift` and a case in
   `TextureFactory.make(id:)`. Override `build()` for one-time setup that needs
   the sample rate, `configure()` for anything derived from `tone` and `motion`
   (it runs at control rate, every 64 samples), and `nextFrame()` for one
   stereo frame.

The library screen, the mixer, the widgets and the intents all read from the
catalog, so a new sound shows up everywhere on its own.

---

## Project layout

```
app/
├── Hush/               app target
│   ├── Audio/          DSP primitives, textures, renderer, AVAudioEngine
│   ├── Model/          settings, mix library, journal, persistence
│   ├── Player/         the controller, Now Playing, alarms, Live Activity
│   ├── Views/          SwiftUI
│   ├── Intents/        the app-side half of App Intents
│   └── Support/        haptics, widget reloads
├── HushWidgets/        widget extension
├── Shared/             compiled into both targets
└── tools/              project and icon generators
```

`Hush.xcodeproj` is generated, not hand-maintained:

```
python3 tools/make_project.py    # rebuild after adding or moving files
python3 tools/verify_project.py  # check every reference resolves
python3 tools/make_icon.py       # redraw the app icon
```

UUIDs are hashed from each object's role, so regenerating is byte-identical and
the project file does not churn in git. You can still add files through Xcode
normally; re-running the generator will simply pick them up from the folder.

---

## Things worth knowing

**The alarm is honest about iOS.** iOS will not wake a suspended app to play
audio. The sunrise ramp works because the app is already alive playing sound all
night. If playback has stopped, a scheduled notification still fires at the
alarm time, but there is no gradual wake-up. The Wake screen says this, and
warns when a sleep timer set to *Stop* would undercut an armed alarm. Setting
the timer to *Fade to quiet* keeps a near-silent bed running so the sunrise can
happen.

**Wind-down only runs while the app is alive**, for the same reason. Labelled as
such on the Wake screen.

**HealthKit is off in this build.** The code is there and permission-gated, but
the capability is deliberately not in `Hush.entitlements`, so the first build
needs one capability to provision instead of two. To turn it on: Signing &
Capabilities → **+ Capability** → HealthKit, on the Hush target. The Settings
toggle detects the refusal and turns itself back off with an explanation until
you do.

**`HushWidgets/HushControl.swift` is the newest API surface in the project**
(iOS 18 Control Center). If a future SDK moves it, that one file can be deleted
and the `HushControl()` line dropped from `HushWidgetsBundle` without touching
anything else.

**In-app purchases are not built, but the seam is.** Every gate-able feature
already asks `Entitlements.isUnlocked(_:)`, which currently always says yes.
Adding a purchase later means implementing that one method against StoreKit and
building a paywall, not auditing the codebase for places that assumed free.

---

## Deliberate omissions

No account, no server, no analytics, no tracking, no network code of any kind.
The app has no `NSAppTransportSecurity` entry because it never makes a request.
