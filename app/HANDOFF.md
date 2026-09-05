# Handoff: Slumbio on TestFlight

The app is on TestFlight and installed on Brett's phone. What is left is the
public link and the automatic build. Read `app/README.md` and the root
`CLAUDE.md` first.

## Where it is (2026-09-05)

- The app is called **Slumbio** on the App Store. Nightjar, Bedside,
  Nightstand, Lowlight, Gloaming, Small Hours and every other single word
  worth having were taken.
- **App Store Connect record `6808987732`**, bundle id
  `dev.brettboggs.nightjar`, SKU `nightjar`, team `NFA8C67SQ8`. The bundle
  id, the Xcode target, the `app/Nightjar/` folder and the Application
  Support directory keep the old name on purpose: they are invisible,
  expensive to move, and moving the last one would orphan the mixes and
  journal already on the phone.
- **Build 1.0 (1)** was archived on this Mac, uploaded, and installed from
  TestFlight on an iPhone 15 Pro Max. It carries the old name and the old
  `/nightjar/` links, because it was built before the rename.
- Internal group **Internal**, automatic distribution on, two testers.
- External group **Testers** exists and build 1 is **Waiting for Review**.
  Beta App Review is a one-time gate before the public link works.
- Test Information is filled in: beta description, feedback email, marketing
  and privacy URLs, review contact and notes.
- `app/Local.xcconfig` said `Y4SP7TWC57`, which is the personal team, not the
  paid one. It now says `NFA8C67SQ8`. That was the reason signing looked odd.

## What is left

1. **Merge PR #1.** Until `main` has it, `brettboggs.dev/slumbio/privacy/`
   is a 404, and that URL is what Apple's beta reviewer will open. This is
   the urgent one.
2. **Turn on App Store Connect API access.** App Store Connect › Users and
   Access › Integrations › App Store Connect API › Request Access, tick the
   box, Submit. Apple reviews the request.
3. **Make the CI key.** Once access is on: Team Keys › +, name it "GitHub",
   role **App Manager**. Download the `.p8` once. Then set three secrets:
   ```
   gh secret set ASC_KEY_ID     --body "<Key ID>"
   gh secret set ASC_ISSUER_ID  --body "<Issuer ID>"
   gh secret set ASC_KEY_P8     < AuthKey_XXXXXXXXXX.p8
   ```
   `APPLE_TEAM_ID`, `DIST_CERT_P12_BASE64` and `DIST_CERT_PASSWORD` are
   already set.
4. **Run it.** Actions › TestFlight › Run workflow. Build 2 carries the
   Slumbio name and the `/slumbio/` links, and automatic distribution puts it
   on every internal tester's phone with nobody clicking anything.

## The distribution certificate

"Apple Distribution: Brett Boggs (NFA8C67SQ8)", expires 2027-09-05. The
private key was generated with openssl on this Mac and never went into the
login keychain, so there is no Keychain Access export step and no GUI
password prompt. The `.p12` in `DIST_CERT_P12_BASE64` holds the leaf, the
Apple WWDR G3 intermediate and the key. It was proved to yield a valid
codesigning identity in a throwaway keychain before the secret was set.

There are only three distribution certificate slots on the account. Do not
let CI create more: the workflow installs this one rather than asking Xcode
to mint a new one on every run.

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
time.

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
