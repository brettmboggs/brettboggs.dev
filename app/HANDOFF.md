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

## Submitted to the App Store, 2026-09-05

Version 1.0 build 11 went to App Review with all four store items in one
submission: the app, the subscription group "Slumbio Plus", both
subscriptions and the lifetime purchase. Apple reviews first-time in-app
purchases with the version, which is why they had to go together, and the
subscriptions could not go without their group.

Release is set to **automatic**, so approval puts it straight on the App
Store with no further click.

Build 11 is also the one in Beta App Review for the public TestFlight link.

### Watch for these, in order of likelihood

- **Guideline 3.1.1, the owner's unlock code.** Unlocking Plus by any means
  other than in-app purchase is against the rule. The entry point is a 1.5
  second long-press on the version line in Settings and nothing advertises
  it, so a reviewer is unlikely to find it, but this is the one deliberate
  risk in the submission. If it is ever cited, delete the `redeem` path in
  `Store.swift` and use an Apple promo code for the lifetime purchase
  instead: same result, sanctioned, and it survives a reinstall.
- **The alarm.** iOS will not wake a suspended app, so the sunrise ramp only
  works when the app is already playing. The review notes say this up front
  because a reviewer who assumes otherwise will file it as a bug.
- **Nobody ran build 11 on a phone before it was submitted.** It compiles and
  the offline checks pass, but the copy changes and the two disclaimer lines
  were never seen on a device.

## Still open

- Beta App Review on build 7. One-time, a day or so. The public link works
  after it passes.
- The three in-app purchases are not created in App Store Connect yet, so the
  paywall has nothing to load on a device. `app/README.md` has the product ids
  and prices. They keep the `dev.brettboggs.nightjar.plus.*` ids.
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
