# App Review information

Apple's reply to the first submission (2026-09-06, submission
`3b8d9695-6a55-430f-b321-68ddb599ae8b`) was **Guideline 2.1, Information
Needed, New App Submission**. It is the questionnaire every developer account
with no review history gets. Nothing in the app was cited as broken and nothing
was rejected on its merits. They asked seven questions and a screen recording.

Apple's own instruction: reply in App Store Connect **and** paste the same text
into App Review Information › Notes, so future submissions already carry it.

Two places to put it, and the thing to paste in both is
**`app/review-notes-field.txt`**, not the markdown below:

1. App Store Connect › the app › the version › **App Review Information** ›
   **Notes**.
2. The **App Review page** for the submission, as a reply, with the screen
   recording attached. Put "Screen recording attached." on the first line.

That field caps at **4000 characters** and neither box renders markdown, so
`review-notes-field.txt` is plain text trimmed to 3992. The longer version
below is the working copy: it says the same things with more room, and is
where to edit before regenerating the short one.

No resubmission is required for the answers alone. A new build is, because the
build that ships now is not the one that was submitted.

---

## Answers

Paste from here down.

### No accounts, no user-generated content

Slumbio has no accounts. There is no registration, no login, no sign-in of any
kind, and therefore no account deletion. No demo credentials are needed to
review the app. Everything is available from first launch.

There is no user-generated content and nothing is shared between users. Saved
mixes and the sleep journal are stored locally on the device and are never
uploaded, so there is nothing to report or block.

### 1. Screen recording

Attached to this reply. It starts at launch, walks the first-run screens, plays
sound, shows all four tabs, opens the purchase flow, and completes a purchase in
the sandbox.

### 2. Purpose and target audience

Slumbio is a sleep sound app for adults who have trouble falling asleep or who
sleep somewhere noisy.

The problem it solves is repetition. Almost every sleep app plays looped audio
files, and once you notice the loop you cannot stop noticing it, which is the
opposite of what a sleep sound is for. Slumbio synthesises its sound on the
device, sample by sample, so it never repeats. You can leave it on all night and
it will not play the same ten seconds twice.

Around the sound sits the rest of a wind-down: a sleep timer, guided breathing,
a sunrise alarm that ramps sound up from silence instead of jolting you awake,
and a local record of how long you slept.

### 3. Setting up and accessing the main features

Nothing to set up. No login, no credentials, no sample files, no permissions
requested at launch.

Launch the app and three short first-run screens appear. Tap through them and
the app opens on Tonight. Four tabs across the bottom:

- **Tonight.** The player. Tap a sound to start it, tap a second to layer it,
  drag the faders to balance them. The sleep timer and bedside mode are here.
  The gear at the top opens Settings.
- **Sounds.** The library. 35 sounds in families: rain, weather, rooms, living
  things and noise. 12 are free and play in full. The rest are marked with the
  Plus symbol and play a 45 second preview before the purchase screen appears.
- **Breathe.** Guided breathing. Two patterns are free, 4 · 7 · 8 and Box. Four
  more come with Plus.
- **Rest.** Sleep tips, the sleep journal, and the settings for the sunrise
  alarm and the wind-down schedule.

One behaviour worth knowing before you test it: **the sunrise alarm requires
the app to be playing.** iOS does not wake a suspended app to start audio, so
the alarm ramps up only from an already running session. The app says this on
the alarm screen rather than promising something iOS will not do. To see it
work, start a sound on Tonight, set the alarm a few minutes out on Rest, and
leave the app in the background with sound playing.

The only permission the app ever asks for is notifications, and only when the
alarm or a bedtime reminder is switched on. Declining it leaves the rest of the
app fully usable.

### 4. External services, tools and platforms

None. Slumbio makes no network requests of any kind.

- All sound is generated on the device by the app's own audio engine. 33 of the
  35 sounds are synthesised in real time from noise generators and filters. The
  other 2 are audio files bundled inside the app, rendered by the developer.
- No data providers, no content feeds, no third-party SDKs, no analytics, no
  crash reporting, no advertising, no tracking.
- No authentication service, because there are no accounts.
- No payment processor other than Apple's In-App Purchase, through StoreKit 2.
- No machine learning or generative services, on device or remote.

Nothing leaves the phone. The sleep journal and saved mixes are written to the
app's own container and stay there. The only outbound links are three buttons
that open Safari to the developer's site for support, privacy policy and terms.

### 5. Regional differences

None. Every feature and every sound is identical in all regions. The app is
English only. In-App Purchase prices follow Apple's price points per
storefront, which is the only thing that differs by region.

### 6. Regulated industry and third-party material

Slumbio is not in a regulated industry. It is not a medical device, it makes no
health or medical claims, and it offers no diagnosis, treatment or therapy. The
breathing screen and the sleep tips each carry a plain disclaimer stating that
they are not medical advice, that anyone with a heart or breathing condition
should talk to a doctor first, and that sleep trouble lasting weeks should go to
a doctor.

No third-party protected material is used. All audio is generated by the app or
rendered by the developer, all artwork and copy are original, and the interface
icons are Apple's SF Symbols.

### 7. In-App Purchase

There is one thing to buy, **Slumbio Plus**, sold three ways. All three unlock
exactly the same features:

| Product | ID | Price | Type |
| --- | --- | --- | --- |
| Slumbio Plus Yearly | `dev.brettboggs.nightjar.plus.yearly` | 19.99 / year, first week free | Auto-renewable subscription |
| Slumbio Plus Monthly | `dev.brettboggs.nightjar.plus.monthly` | 3.99 / month | Auto-renewable subscription |
| Slumbio Plus Lifetime | `dev.brettboggs.nightjar.plus.lifetime` | 39.99 once | Non-consumable, Family Sharing on |

The two subscriptions are in one group, "Slumbio Plus". All three products were
configured and submitted alongside this version.

**What Plus adds**, over a free tier that is a complete nightly routine on its
own:

- All 35 sounds instead of 12.
- Six sounds layered at once instead of two.
- All 6 breathing patterns instead of 2, including a custom one.
- Wind-down routines, which chain breathing into a mix and the timer.
- The sunrise alarm and the bedtime schedule.
- Unlimited saved mixes instead of 2.
- The full sleep journal instead of the last 7 nights.

**How to reach the purchase screen.** Any of these:

- Settings (the gear at the top of Tonight), then the Plus row at the top.
- Sounds tab, then tap any sound carrying the Plus symbol. It previews for 45
  seconds first, then the purchase screen appears.
- Breathe tab, then tap Coherent, Long Exhale or Physiological Sigh.
- Rest tab, then the Sunrise alarm row.

The purchase screen shows all three products with title, price, duration and
renewal terms, has Restore, and links to the privacy policy and terms. Yearly is
preselected. Restore Purchases is also in Settings.

Paste ends here.

---

## The screen recording

Apple wants it captured on a physical device on the current iOS, starting at
launch, showing the typical flow and the purchase. One take, roughly two
minutes, no narration needed. Delete and reinstall the app first so the
first-run screens appear.

1. Home screen, tap the Slumbio icon. Let it launch.
2. Through the three first-run screens.
3. Tonight: tap a sound, let it play, tap a second one, move a fader.
4. Set the sleep timer. Show bedside mode.
5. Sounds tab: scroll the library. Tap a free sound, it plays. Tap a Plus sound,
   let the preview run a few seconds, let the purchase screen appear.
6. On the purchase screen: show all three products, scroll to the renewal terms,
   the Restore button and the two links.
7. Buy one in the sandbox. Show a Plus feature working afterwards, easiest is
   layering more than two sounds, or the Sunrise alarm row on Rest.
8. Breathe tab: start a free pattern, let one cycle run.
9. Rest tab: scroll the tips and the journal.
10. Settings: scroll it to the bottom.

Skip the alarm firing. It needs real time to pass and the notes explain it.

## Before replying

- [ ] Build without the hidden unlock is on App Store Connect and is the build
      attached to version 1.0.
- [ ] That build installed from TestFlight on a real phone and actually used,
      end to end. Apple asked for this directly, and no build had been run on a
      device before the first submission.
- [ ] Screenshots show the app in use, not the first-run screens. The four in
      `public/slumbio/` are the app in use.
- [ ] Notes field filled in.
- [ ] Reply sent on the App Review page with the recording attached.
