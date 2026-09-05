# Hush

An iPhone sleep-sound app with two kinds of sound in one engine.

Most of the library is **synthesized** in real time, a sample at a time, from
noise and filters. Those never loop, because there is nothing to loop.

The **Recordings** shelf is real audio, streamed from the bundle and looped with
a crossfade. Both kinds are just voices in the same renderer, so they mix
together, share the sleep-timer fade and the sunrise ramp, and take the same two
shaping controls.

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

**Shaping.** Every sound has two continuous controls beyond level, and the
labels change per sound: Glass/Drops for light rain, Metal/Drips for a tin roof,
Coals/Crackle for a fire, Tilt/Drift for a recording. On a synthesized texture
these reach into the generator itself. On a recording, Tilt is a shelf pair and
Drift is a slow level wander that keeps a ten-minute loop from settling into
something the ear can memorise.

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
 ├─ one VoiceSlot per catalog sound, all allocated at launch
 │   ├─ Texture subclass        → generates a stereo frame
 │   └─ RecordingTexture        → drains a ring buffer
 │        ↑ filled by a reader thread: decode → crossfade loop → resample
 ├─ per-voice gain ramp
 ├─ master ramp   (fade in / sleep timer / sunrise)
 ├─ tilt shelves  (one global warm↔bright control)
 └─ soft clipper
```

Recordings deliberately go through the renderer rather than through a separate
`AVAudioPlayerNode`. A player node would be less code, but its output would
bypass the master ramp, and the sleep-timer fade, the sunrise and the limiter
would then behave differently for files than for synthesis. One path is worth
the extra work.

Three decisions drive everything else:

**Every sound is pre-allocated.** Every texture exists from launch, whether or
not it is in the mix. Turning a sound on is a gain change, so nothing is
allocated, attached or detached while audio is running, and nothing can click.
The cost is about 30 KB of filter state, plus 1 MB of ring buffer per recording.

**Recordings stream, they do not load.** Ten minutes of 44.1 kHz stereo is over
200 MB as float, so nothing is held in memory. A single background queue tops up
a two-second ring buffer for every active recording, waking every 400 ms. The
readers stop when playback stops.

**The loop is crossfaded, not butt-joined.** Splicing the end of a recording
onto its start leaves a step in the waveform, and on broadband noise a step is
an audible tick every ten minutes, all night. The last two seconds fade out
under the first two fading in, which on noise is inaudible.

**Nothing blocks the audio thread.** Parameters are plain `Float` fields written
from the main thread and read on the audio thread, then smoothed or ramped
before they reach the signal. No locks, no allocation, no weak references. A
missed update costs one block, about 10 ms, and is inaudible. The contract is
written out on `Renderer`.

Textures are built from primitives in `Audio/DSP.swift`: xorshift noise, a pink
filter, a leaky integrator for brown, RBJ biquads, band-limited random walks for
gusts and swell, and a fixed-capacity grain bank for raindrops, fire crackle,
cricket chirps and rail clatter.

### Adding a recording

1. Drop the `.m4a` into `Hush/Resources/Recordings/`.
2. Add a `SoundKind` to `SoundCatalog.all` in `Shared/SoundCatalog.swift` with
   `source: .recording(resource: "your-file-name")`, no extension.
3. `python3 tools/make_project.py`

Any sample rate, any length, mono or stereo. The reader resamples to whatever
the output route is running at, and picks its crossfade length from the file
(two seconds, or a quarter of the file if it is shorter than eight).

### Adding a synthesized sound

1. Add a `SoundKind` to `SoundCatalog.all`, leaving `source` at its default.
   `toneLabel` and `motionLabel` name the two shaping sliders for this sound.
2. Add a `Texture` subclass in `Audio/Textures.swift` and a case in
   `TextureFactory.make(_:)`. Override `build()` for one-time setup that needs
   the sample rate, `configure()` for anything derived from `tone` and `motion`
   (it runs at control rate, every 64 samples), and `nextFrame()` for one
   stereo frame.

Either way, the library screen, the mixer, the widgets and the intents all read
from the catalog, so a new sound shows up everywhere on its own.

---

## Project layout

```
app/
├── Hush/               app target
│   ├── Audio/          DSP, textures, file streaming, renderer, AVAudioEngine
│   ├── Resources/      bundled recordings
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

**Bundled audio is about 29 MB and will grow.** Both recordings are 194 kbps
stereo AAC. Two things worth knowing as the shelf fills up: brown noise
compresses well and loses almost nothing in mono, which halves each file; and
past a few sounds, the right answer is On-Demand Resources so the App Store
download stays small and sounds are fetched on first use. Neither is worth doing
for two files. If the git repository itself gets heavy, Git LFS is the fix.

**`HushWidgets/HushControl.swift` is the newest API surface in the project**
(iOS 18 Control Center). If a future SDK moves it, that one file can be deleted
and the `HushControl()` line dropped from `HushWidgetsBundle` without touching
anything else.

**Testing a purchase costs nothing.** The scheme points at `Hush.storekit`, so
buying, restoring and Ask-to-Buy all work in the simulator with no App Store
Connect setup. To reset: Xcode → Debug → StoreKit → Manage Transactions.

---

## Pricing

**$4.99 once. No subscription, ever.** Family-shareable, so one purchase covers
a household. Product ID `dev.brettboggs.hush.pro`, a non-consumable.

The category norm is fifty to seventy dollars a year for what amounts to noise.
Undercutting that by an order of magnitude is the position, not a discount, and
the free tier is built so that people recommend the app rather than resent it.

| Free forever | Hush Pro |
| --- | --- |
| All 19 sounds, recordings included | Everything in Free |
| Shaping controls on every sound | Up to 8 layers at once |
| 3 layers at once | Unlimited saved mixes |
| 3 saved mixes | Sunrise alarm and wind-down |
| Sleep timer, fades, bedside mode | Full sleep journal |
| Widgets, Control Center, Siri | |
| Background and locked-screen audio | |

Nothing that makes the app *work* is behind the wall. What you pay for is depth
and waking up.

Everything gate-able routes through `Entitlements`, and the paywall is raised by
`PlayerController.requestUpgrade(_:)` with the reason the person hit it, so the
headline always answers what they were actually trying to do. Changing where a
line sits means editing one policy file, not hunting through views.

### Before you ship

1. App Store Connect → your app → **In-App Purchases** → new **Non-Consumable**
   with product ID `dev.brettboggs.hush.pro`, price tier $4.99, Family Sharing
   on.
2. Paste the description from `Hush.storekit` so the two agree.
3. Attach the IAP to your first review submission, or it will not be reviewed.
4. Apple takes 30%, or 15% under the Small Business Program, which you qualify
   for under a million a year in proceeds. Enrol; it is a form, and it is the
   difference between $3.49 and $4.24 a sale.

---

## Deliberate omissions

No account, no server, no analytics, no tracking, no network code of any kind.
The app has no `NSAppTransportSecurity` entry because it never makes a request.
