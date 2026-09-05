# Nightjar

An iPhone sleep app. Sound that never loops, breathing you can see, and a
routine that chains the two into the sleep timer.

Working name. To rename it, change `APP_NAME` and `BUNDLE_ID` in
`tools/make_project.py`, the display name in `Nightjar/Info.plist`, the three
product ids in `Nightjar/Model/Store.swift` and `Nightjar.storekit`, and the
folder name. Everything else reads from those.

---

## What it is

**One living thing.** A soft body of light sits behind every screen. It
breathes six times a minute at rest, swells with the audio, glides between
tabs, and in a breathing session it is the instruction: the whole screen
fills on the inhale and empties on the exhale, with a tap at each turn and a
breath sound under it. `Nightjar/Living/Orb.metal` is the shader,
`LivingCanvas.swift` is the SwiftUI host, and `RootView` owns the one
instance that lives behind the tabs.

**Sounds.** 35, most of them synthesised in real time from noise and filters,
so there is nothing to loop. Two are pre-rendered files streamed with a
crossfade; they are the only sounds here that repeat. Each has a level and two shaping controls that reach into the
generator. Up to six layer at once.

**Breathe.** 4·7·8, box, coherent, long exhale, the physiological sigh, and a
custom one. Two to fifteen minutes. The session ends at the end of a cycle,
never mid-breath.

**Wind down.** One tap: a breathing session, then the mix, then the sleep
timer. The bedtime schedule can start it on its own while the app is open.

**Rest.** Thirty short, practical notes on sleep, one surfaced each night on
the Tonight screen. A sleep journal that lives on the phone. A sunrise alarm
that climbs from silence.

**Bedside.** A clock at 2% brightness with the controls hidden until you touch
it.

No account, no server, no analytics, no tracking, no network code of any kind.

---

## Getting it on a phone

You need a Mac with **Xcode 16 or newer** and an Apple ID.

```
cd app
./tools/install.sh        # phone plugged in: builds, installs, launches
```

or open `app/Nightjar.xcodeproj`, pick your team under Signing & Capabilities,
choose your iPhone and press ⌘R. There is one target and no entitlements, so
a free Apple ID can sign it (it lasts seven days at a time on a free account).

The simulator runs the app and the store (the scheme points at
`Nightjar.storekit`, so buying and restoring work with no App Store Connect
setup), but audio, haptics, the lock screen and the shader are only worth
judging on hardware.

`Nightjar.xcodeproj` is generated, not hand-maintained:

```
python3 tools/make_project.py    # rebuild after adding or moving files
python3 tools/verify_project.py  # check every reference resolves
python3 tools/check_swift.py     # offline consistency checks on the sources
python3 tools/make_icon.py       # redraw the app icon
```

---

## TestFlight, automatically

`.github/workflows/testflight.yml` archives the app on a GitHub macOS runner
and uploads it to TestFlight on every push to `main` that touches `app/`.
Testers get each build automatically through the TestFlight app. That is the
native equivalent of over-the-air updates: the code has to go through Apple,
but nobody has to plug anything in and nobody has to be asked.

macOS runners are free on public repositories, and this one is public.

### One-time setup

Everything below is free except the Apple Developer Program, which is
**$99 a year** and unavoidable for TestFlight and the App Store.

1. **Enrol** at developer.apple.com. Note the ten-character **Team ID** under
   Membership.

2. **Create the app record.** App Store Connect › Apps › + › New App. Platform
   iOS, name Nightjar (or whatever it becomes), bundle id
   `dev.brettboggs.nightjar` (register it first under Certificates, IDs &
   Profiles › Identifiers if it is not in the list), SKU anything.

3. **API key.** App Store Connect › Users and Access › Integrations › App Store
   Connect API › Team Keys › +. Name it "GitHub", role **App Manager**. Download
   the `.p8` once (it cannot be downloaded again) and note the **Key ID** and
   the **Issuer ID** at the top of that page.

4. **Certificates.** Two of them. Automatic signing archives with a
   development identity and only re-signs for distribution during the export,
   so a runner holding just the distribution certificate fails the archive
   with "No signing certificate iOS Development found".

   The cheap way to get both without a Keychain Access export and its GUI
   password prompt is to make the keys yourself:

   ```
   openssl genrsa -out dist.key 2048
   openssl req -new -key dist.key -out dist.csr \
     -subj "/emailAddress=you@example.com/CN=Your Name/C=US"
   ```

   Upload `dist.csr` at developer.apple.com › Certificates › + ›
   **Apple Distribution**, download the `.cer`, then:

   ```
   curl -sfSL -o wwdr.cer https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer
   openssl x509 -inform DER -in wwdr.cer -out wwdr.pem
   openssl x509 -inform DER -in distribution.cer -out dist.pem
   openssl pkcs12 -export -legacy -inkey dist.key -in dist.pem \
     -certfile wwdr.pem -out dist.p12 -passout "pass:<password>"
   base64 -i dist.p12 | tr -d '\n' | pbcopy
   ```

   Repeat the whole thing with a second key for **Apple Development**. Use the
   same password for both.

5. **Secrets.** GitHub › the repo › Settings › Secrets and variables › Actions
   › New repository secret, seven times:

   | Secret | Value |
   | --- | --- |
   | `APPLE_TEAM_ID` | the Team ID |
   | `ASC_KEY_ID` | the Key ID |
   | `ASC_ISSUER_ID` | the Issuer ID |
   | `ASC_KEY_P8` | the whole contents of the `.p8` file |
   | `DIST_CERT_P12_BASE64` | the base64 of the distribution `.p12` |
   | `DEV_CERT_P12_BASE64` | the base64 of the development `.p12` |
   | `DIST_CERT_PASSWORD` | the password, the same for both |

6. **Run it.** Actions › TestFlight › Run workflow, or push anything under
   `app/` to `main`. The first run takes ten to fifteen minutes. The build
   number is the workflow run number, so it always goes up.

7. **Testers.** App Store Connect › the app › TestFlight. Internal testers
   (up to 100 people on your team) get builds the moment they finish
   processing. External testers (up to 10,000) join through a **public link**;
   the first external build goes through a one-time Beta App Review, a day or
   so. Everyone installs the TestFlight app and taps the link. New builds
   install themselves.

If you would rather skip the certificate step entirely, Xcode Cloud does the
same job with cloud-managed signing and 25 free compute hours a month: in
Xcode, Product › Xcode Cloud › Create Workflow, connect the GitHub repo, and
set the workflow to archive and deploy to TestFlight on pushes to `main`.

---

## Pricing

Three doors into the same thing. All unlock `isPlus`.

| Plan | Price | Notes |
| --- | --- | --- |
| Yearly | $19.99 | First week free. Preselected. |
| Lifetime | $39.99 | One payment, family-shareable. |
| Monthly | $3.99 | Exists so yearly has something to be cheaper than. |

The category norm is sixty to seventy dollars a year. This is a third of that
with a real free tier underneath it:

| Free forever | Plus |
| --- | --- |
| 12 sounds | All 35 |
| 2 layers | 6 layers |
| 2 saved mixes | Unlimited |
| 4·7·8 and box breathing | Every pattern, plus your own |
| The default wind-down routine | Edit the routine |
| Sleep timer, fades, bedside mode | Sunrise alarm |
| Every tip, last 7 nights of the journal | The whole journal |

The paywall is never a gate. It appears when someone taps a Plus thing, with a
headline that answers what they were trying to do; once, softly, after their
first full night; and from Settings. Locked sounds play for 45 seconds before
the ask, because hearing it is the argument. A local notification fires two
days before a free week becomes a charge.

### Before you ship

1. App Store Connect › the app › **Subscriptions** › create a group named
   "Nightjar Plus" with two auto-renewable subscriptions,
   `dev.brettboggs.nightjar.plus.yearly` ($19.99, introductory offer: free,
   1 week) and `dev.brettboggs.nightjar.plus.monthly` ($3.99).
2. **In-App Purchases** › one non-consumable,
   `dev.brettboggs.nightjar.plus.lifetime` ($39.99), Family Sharing on.
3. Paste the descriptions from `Nightjar.storekit` so the two agree.
4. Attach all three to the first submission, or they will not be reviewed.
5. Enrol in the **Small Business Program** (under a million a year in
   proceeds). It is a form, and it is the difference between 70% and 85%.
6. The privacy policy and terms the app links to live at
   `brettboggs.dev/nightjar/privacy/` and `/terms/`. App Store Connect wants
   the same URLs.

---

## How the sound works

```
Renderer (audio thread)
 ├─ one VoiceSlot per catalog sound, all allocated at launch
 │   ├─ Texture subclass        → generates a stereo frame
 │   └─ RecordingTexture        → drains a ring buffer
 │        ↑ filled by a reader thread: decode → crossfade loop → resample
 ├─ BreathGuideTexture         → the breath sound, outside the mix
 ├─ per-voice gain ramp
 ├─ master ramp   (fade in / sleep timer / sunrise)
 ├─ tilt shelves  (one global warm↔bright control)
 └─ soft clipper
```

**Every sound is pre-allocated.** Turning a sound on is a gain change, so
nothing is allocated, attached or detached while audio is running, and nothing
can click.

**The streamed files stream, they do not load.** A single background queue
tops up a two-second ring buffer for each active one. The loop is crossfaded,
not butt-joined.

**Nothing blocks the audio thread.** Parameters are plain `Float` fields
written from the main thread and read on the audio thread, then smoothed or
ramped before they reach the signal. The contract is written out on
`Renderer`.

Textures are built from primitives in `Audio/DSP.swift`: xorshift noise, a
pink filter, a leaky integrator for brown, RBJ biquads, band-limited random
walks for gusts and swell, and a fixed-capacity grain bank for raindrops, fire
crackle, cricket chirps and rail clatter.

### Adding a synthesised sound

1. Add a `SoundKind` to `SoundCatalog.all` in `Model/SoundCatalog.swift`.
   `toneLabel` and `motionLabel` name the two shaping sliders. `isFree: true`
   puts it on the free shelf.
2. Add a `Texture` subclass in `Audio/` and a case in `TextureFactory.make`.
   Override `build()` for one-time setup that needs the sample rate,
   `configure()` for anything derived from `tone` and `motion`, and
   `nextFrame()` for one stereo frame.
3. `python3 tools/check_swift.py` confirms the catalog and the factory agree.

### Adding a streamed file

1. Drop the `.m4a` into `Nightjar/Resources/Recordings/`.
2. Add a `SoundKind` with `source: .recording(resource: "file-name")`.
3. `python3 tools/make_project.py`

---

## Project layout

```
app/
├── Nightjar/
│   ├── Audio/       DSP, textures, file streaming, renderer, AVAudioEngine
│   ├── Living/      the orb: Metal shader and SwiftUI host
│   ├── Model/       catalog, mixes, settings, plan, store, patterns, tips
│   ├── Player/      the controller, breath sessions, lock screen, reminders
│   ├── Views/       SwiftUI
│   ├── Support/     theme, haptics, formatters
│   └── Resources/   the two streamed audio files
├── Nightjar.storekit   local store for the simulator
├── Signing.xcconfig    includes the gitignored Local.xcconfig
└── tools/              project, verifier, installer, icon
```

---

## Things worth knowing

**The alarm is honest about iOS.** iOS will not wake a suspended app to play
audio. The sunrise ramp works because the app is already alive playing sound
all night. If playback has stopped, a scheduled notification still fires at
the alarm time, but there is no gradual wake-up. The Mornings sheet says this.

**The bedtime schedule only runs while the app is open**, for the same reason.

**No widgets, Live Activity, Siri or Health in this build.** An earlier
version had all four. They need an App Group, which a free Apple ID cannot
provision, and every one of them was a way for the first build to fail. They
are in git history and can come back once the app is on TestFlight.

**Testing a purchase costs nothing.** The scheme points at `Nightjar.storekit`,
so buying, restoring and the free week all work in the simulator. To reset:
Xcode › Debug › StoreKit › Manage Transactions.
