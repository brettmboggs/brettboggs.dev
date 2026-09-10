# The App Store listing

Everything App Store Connect asks for, in one place, so the live listing and
the repo never drift. The description also lives on its own in
`store-description.txt`, because that is the file `REVIEW-NOTES.md` points at
for the Guideline 3.1.2 check.

**Do not paste the description until the 1.1 build is approved.** It describes
the nights chart and the breathing ring, and a product page that claims
something the shipped binary does not do is a Guideline 2.3.1 rejection.

## The three fields Apple actually searches

Apple indexes the app name, the subtitle and the keyword field. It does not
index the description. It also treats a word used twice across those three
fields as used once, and treats plurals as the same word, so nothing below
repeats anything above it.

| Field | Limit | Value | Used |
| --- | --- | --- | --- |
| App Name | 30 | `Slumbio: Sleep Sounds & Alarm` | 29 |
| Subtitle | 30 | `White Noise, Breathing, Timer` | 29 |
| Keywords | 100 | `rain,brown,pink,ocean,fan,insomnia,relax,calm,nap,bedtime,nature,ambient,tinnitus,sunrise,aid,waves` | 99 |

Twenty-four distinct words, no duplicates. Apple joins words across the three
fields when it matches a query, so "sleep timer", "white noise machine",
"brown noise", "rain sounds", "sunrise alarm" and "sleep aid" all match
without any of those phrases being written out anywhere.

The old name was `Slumbio` alone, which is a coined word nobody types. The
name field is the heaviest-weighted of the three and it was spending all
thirty characters on a term with no search volume behind it.

Keywords go in as one comma-separated string with **no spaces after the
commas**. A space costs a character and buys nothing.

## Promotional Text

170 characters, above the description, and the only field here that can be
changed without a review. Use it for whatever is true this month.

```
Thirty-five sounds, and thirty-three of them are made as they play, one frame at a time. Nothing loops, so there is no seam to hear.
```

## Description

`store-description.txt`, pasted whole. 3261 of 4000 characters.

Only the first three lines show before "more", so the first paragraph carries
the whole argument. The SLUMBIO PLUS block at the bottom and the two links
under it are what satisfies Guideline 3.1.2 and they are not optional; see
`REVIEW-NOTES.md`.

## What's New, for 1.1

```
The screen no longer washes out the words in front of it. The light behind
every screen is tone mapped now, so it stays a warm body instead of a white
hole, and there is a veil under it wherever a screen puts text.

Breathe draws the pattern you picked as a ring before you start, one arc per
phase, so 4-7-8 looks lopsided and box looks square.

Rest draws your last two weeks as a chart with your average marked across it,
instead of one line of small print.

A new icon, and Health, widgets and Siri if you want them.
```

## Screenshots

Eight, at 1320 x 2868, built by `tools/shots/capture.sh` and
`tools/shots/compose.py`. Upload them in this order; Apple shows the first
three in search results, so those three carry the argument.

| # | Screen | Caption |
| --- | --- | --- |
| 1 | Tonight, playing | Sound that never repeats. |
| 2 | Breathe | Breathing you can see. |
| 3 | Sounds | Thirty-five sounds. Six at once. |
| 4 | Wind down | One tap for the whole night. |
| 5 | Mornings | Wake to light, not to a siren. |
| 6 | Rest | Two weeks of nights. |
| 7 | Bedside | A clock at two percent. |
| 8 | Settings | No account. No server. |

A 6.9 inch set is enough: App Store Connect scales it down for every smaller
iPhone. There is no iPad build, so there is no iPad set.

## Still missing, in order of what it would be worth

1. **An app preview video.** Every app above us in the category has one, and
   it is the only asset that can show sound being shaped or the orb
   breathing. 15 to 30 seconds, portrait, captured on a device.
2. **Ratings.** Zero of them is the single biggest gap against ShutEye's
   350,000. The prompt already fires after a good night; it needs volume, not
   more code.
3. **Localisation.** The listing is English only.

## What the competition looks like

Checked 2026-09-10, so it will have moved.

| App | Rating | Ratings | Shots | Preview | Year |
| --- | --- | --- | --- | --- | --- |
| BetterSleep | 4.7 | 391k | 9 | yes | $59.99 |
| Calm | 4.8 | 1.98m | 6 | yes | $69.99 |
| ShutEye | 4.8 | 350k | 8 | yes | $59.99 |
| Sleep Cycle | 4.7 | 29k | 10 | yes | $39.99 |
| Endel | 4.6 | 34k | 8 | yes | $49.99 |
| Slumbio | n/a | 0 | 8 | no | $19.99 |

They all lead with a sleep score and a hypnogram from overnight tracking,
which this app deliberately does not do. The argument here is the opposite
one: no microphone, no account, nothing leaving the phone, and a third of the
price. The listing should keep making that argument rather than pretending to
be a tracker.
