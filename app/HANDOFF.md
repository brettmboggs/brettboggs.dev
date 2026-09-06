# Slumbio: where it stands

The app is on TestFlight, it installs from TestFlight on a phone, and every
push to `main` that touches `app/` builds and uploads on its own. Read
`app/README.md` and the root `CLAUDE.md` first.

## State (2026-09-05)

- **Slumbio** on the App Store, record `6808987732`, bundle id
  `dev.brettboggs.nightjar`, SKU `nightjar`, team `NFA8C67SQ8`. Nightjar,
  Bedside, Nightstand, Lowlight, Gloaming, Slowlight and Small Hours were all
  taken. The bundle id, the Xcode target, the `app/Nightjar/` folder and the
  Application Support directory keep the old name on purpose: they are
  invisible, and renaming the last one would orphan the mixes and journal
  already on the phone.
- **Internal group** "Internal", automatic distribution on, two testers, both
  getting builds.
- **External group** "Testers" holds build 1.0 (7) in Beta App Review. The
  public link is `https://testflight.apple.com/join/rve1Grra` and goes live
  when that review passes. Build 1 was pulled out of review first: it carried
  the old name and the old `/nightjar/` links.
- **CI** is `.github/workflows/testflight.yml`. All seven secrets are set. A
  push to `main` under `app/` archives, uploads, and automatic distribution
  puts it on every internal tester's phone. Nobody clicks anything.
- Site pages live at `/slumbio/`, `/slumbio/privacy/`, `/slumbio/terms/`.
  `/nightjar/*` redirects to them so build 1 keeps finding its policies.

## Three things that broke CI, so nobody rediscovers them

1. **`Local.xcconfig` held the wrong team.** It said `Y4SP7TWC57`, which is
   the personal team. The paid one is `NFA8C67SQ8`. The certificate's OU is
   the team id; the name in parentheses is not.

2. **The archive needs a development certificate, not a distribution one.**
   Automatic signing archives with `Apple Development` and only re-signs for
   distribution during `-exportArchive`. A runner holding only the
   distribution certificate fails with "No signing certificate iOS
   Development found". Hence two certificates and two secrets.

   Pinning `CODE_SIGN_IDENTITY` to `Apple Distribution` instead does **not**
   work: automatic signing rejects a manually specified identity with
   "conflicting provisioning settings". Do not try it again.

3. **Cloud signing needs an Admin key.** With an App Manager key the export
   fails with "Cloud signing permission error / No profiles for
   dev.brettboggs.nightjar were found". The key `GitHub CI` (`J4WN9W9CST`) is
   Admin. Keys cannot be re-scoped after creation, so a narrower key means
   making a new one.

   The alternative is pinning a provisioning profile as an eighth secret,
   which is least privilege but breaks every year when the profile expires.

## An internal tester showing "No Builds Available"

Automatic distribution hands a build to the testers who are in the group at
distribution time. Someone added afterwards gets nothing until the next build
lands. It is not a permissions problem and there is nothing to fix; ship
another build.

## Certificates

- `Apple Distribution: Brett Boggs (NFA8C67SQ8)`, expires 2027-09-05.
- `Apple Development: Brett Boggs (Y4SP7TWC57)`, expires 2027-09-05.

Both private keys were generated with `openssl` and never touched the login
keychain during creation, which is what avoids the Keychain Access export and
its GUI password prompt. Both identities are now installed in the login
keychain as well, so local archives work and the `.p12` files can be rebuilt
from there if a secret ever needs re-setting. `app/README.md` step 4 has the
full recipe.

There are only three distribution certificate slots on the account. The
workflow installs the certificate rather than asking Xcode to mint one per
run, so it does not burn them.

## Doing a build by hand

```
python3 app/tools/make_project.py
xcodebuild archive -project app/Nightjar.xcodeproj -scheme Nightjar \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/Slumbio.xcarchive -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION=<n>
xcodebuild -exportArchive -archivePath build/Slumbio.xcarchive \
  -exportOptionsPlist build/ExportOptions.plist -exportPath build/export \
  -allowProvisioningUpdates
```
`method` = `app-store-connect`, `destination` = `upload`, `signingStyle` =
`automatic`, `teamID` = `NFA8C67SQ8`. The build number has to go up every
time. CI uses the workflow run number, so it always does.

## Submitted to the App Store, 2026-09-05. Came back 2026-09-06.

Version 1.0 build 11 went to App Review with all four store items in one
submission: the app, the subscription group "Slumbio Plus", both subscriptions
and the lifetime purchase. Apple reviews first-time in-app purchases with the
version, which is why they had to go together, and the subscriptions could not
go without their group.

Release is set to **automatic**, so approval puts it straight on the App Store
with no further click.

### What came back

**Guideline 2.1, Information Needed, New App Submission.** Submission
`3b8d9695-6a55-430f-b321-68ddb599ae8b`. Not a rejection on the merits. It is the
questionnaire Apple sends every developer account with no review history: seven
questions about what the app is and a screen recording made on a real device.
Nothing in the app was cited as broken.

The answers are written out in `app/REVIEW-NOTES.md`, ready to paste into App
Review Information › Notes and into the reply on the App Review page. Apple asks
for both, so the notes carry forward to later submissions.

Apple also said, in as many words, to run the build through testing on a
physical device first. Build 11 never was.

### The unlock code is gone

The hidden long-press on the version line and the `redeem` path in `Store.swift`
were removed. They were a real Guideline 2.3.1 problem, hidden and undocumented
functionality, and they were going to be found eventually. `isPlus` is now
`isEntitled` and nothing else. Comp yourself with an Apple promo code for the
lifetime purchase: sanctioned, free, and it survives a reinstall.

That makes this a code change, so a new build has to go up and be attached to
version 1.0 before the reply is sent. Pushing to `main` builds it.

### Still worth watching on the next pass

- **The alarm.** iOS will not wake a suspended app, so the sunrise ramp only
  works when the app is already playing. `REVIEW-NOTES.md` says this up front
  because a reviewer who assumes otherwise will file it as a bug.
- **Near-silent background audio.** "Fade to quiet" keeps a very low bed running
  so the sunrise alarm has something to ramp. Guideline 2.5.4 exists for apps
  that play silence to stay alive in the background. This one is user-chosen and
  serves a feature the user switched on, which is the defence, but it is the
  next most likely thing to be asked about.

## Still open

- Beta App Review on build 7. One-time, a day or so. The public link works
  after it passes.
- Reply to App Review with `app/REVIEW-NOTES.md` and the screen recording. The
  recording is the only part nobody can do for you: real device, current iOS,
  starting at launch, through a sandbox purchase. Shot list is in that file.
- The site pages still live under a `/slumbio/` route while the repo folder
  and bundle id say nightjar. That is deliberate; see above.

## Rules from the repo you must keep

- No mention of AI, Claude, or assisted authorship anywhere: commits, PR
  text, code, App Store metadata. No Co-Authored-By trailers.
- No em-dashes in copy. Stoic, short.
- Do not spend money.
- Xcode edits `app/Nightjar.xcodeproj` when opened; never hand-edit it,
  regenerate with `python3 app/tools/make_project.py`. Do not commit the
  `DEVELOPMENT_TEAM` line it writes when `Local.xcconfig` exists.
- `app/Local.xcconfig` holds the team id and is gitignored. Leave it.

## If the build breaks

`python3 app/tools/check_swift.py` and `python3 app/tools/verify_project.py`
are the offline checks. The engine in `app/Nightjar/Audio/` is the part Brett
wants kept.
