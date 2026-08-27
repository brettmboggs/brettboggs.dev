---
title: 'Apparent Low'
description: 'An extraction agent and eval harness for state DOT bid tabulations.'
date: 2026-08-26
tags: ['ai engineering', 'construction']
draft: true
---

When a state DOT opens bids, the results publish as a bid tabulation: every
proposal, every bidder, every pay item and unit price, laid out in wide tables
across sometimes hundreds of PDF pages. The lowest bidder is the *apparent
low*. Estimators mine these documents for unit-price history, and an entire
commercial industry exists to sell them back as structured data.

Apparent Low extracts them with an LLM agent. The point is not the extraction.
The point is the measurement around it: anyone can prompt a model to read a
table. The work is knowing, with numbers, when it read the table wrong.

## Use it on a real letting

No install, no account setup beyond a Claude subscription, nothing to
download but the bid tab itself. Five minutes, start to spreadsheet:

1. **Get the bid tab PDF** for your letting, from Bid Express, your DOT's
   letting results page, or wherever your state posts them after award.
2. **Open the reader prompt:** [field-prompt.txt](/apparent-low/field-prompt.txt).
   Select all of it (Ctrl+A) and copy (Ctrl+C).
3. **Go to [claude.ai](https://claude.ai)**, start a new chat, paste the
   prompt, attach the PDF with the paperclip button, and send.
4. **You get back:** the bidder ranking per contract, the full pay-item
   schedule as data you can paste straight into Excel, an arithmetic check of
   every line with anything off flagged, and a short read on where the low
   bidder won it.

This is the complete tool. The developer install further down is the testing
lab that proves its accuracy, not a better version of it. If a number comes
back wrong against the PDF, that is exactly the feedback this project runs
on: [say so here](https://github.com/brettmboggs/apparent-low/issues).

## How it is measured

**Structural scoring, never text diffing.** Items pair by item code and line
number. Recall says what was missed; precision says what was invented. The
two failure modes are kept apart because they are not equally bad.

**Dollar-weighted error.** A $2,000,000 extension read as $200,000 and a $200
item off by a cent are one error each by row count. They are not one error
each. Errors are weighted by the money they touch, and a missed item is
charged at one hundred percent of its dollars.

**Arithmetic self-verification.** Bid tabs carry their own ground truth:
quantity times unit price equals the extension on every line, and extensions
sum to each bidder's stated total. The harness checks both on every
extraction, so hallucinated numbers get caught even on documents nobody has
labeled. The same gate validates the ground truth itself before a label is
accepted as truth.

**Diagnosis, not just scores.** Every mismatch is classified into a failure
taxonomy drawn from how wide-table extraction actually fails: column drift,
digit slips, merged rows, bidder misattribution, invented items. A prompt
revision can act on "v003 fixed column drift but introduced digit slips" in a
way it cannot act on "accuracy went down."

**Measured self-repair.** When an extraction fails its own arithmetic, the
agent gets its exact failing lines back for one repair turn. One,
deliberately: a loop that iterates until the arithmetic passes would teach
the model to fabricate consistent numbers instead of reading the page. The
eval reports first-pass and post-repair accuracy separately, so the loop's
value is a number, not a claim.

All money runs through exact scaled-integer math, because unit prices on DOT
tabs carry five decimals and sub-cent steel pricing is real. The scorer has
its own test suite, because a broken scorer reports fiction with confidence.

## Results so far

| prompt | corpus | item recall | item precision | field accuracy | $-weighted error |
|---|---|---|---|---|---|
| v001 | 1 letting, 20 items, 4 bidders | 100% | 100% | 100% | 0.0% |

One small, clean letting, extracted in 78 seconds with every one of its 80
priced bids exact. That proves the pipeline end to end, not the problem
solved. The corpus's larger lettings run to 900,000 characters of tabulation,
several times a model's context window, with bidders split across repeated
page passes. Splitting by call order and reassembling with the harness
verifying the seams is the open work, and the results table only ever means
as much as the corpus is hard.

## For developers

The repo is public: [github.com/brettmboggs/apparent-low](https://github.com/brettmboggs/apparent-low).
Running the testing harness requires Node.js and a Claude Code subscription.
No API key, no marginal cost:

```
git clone https://github.com/brettmboggs/apparent-low
cd apparent-low && npm install
npm test                                      # the scorer proves itself
npm run extract corpus/text/iowa-2026-06-09.txt v001
npm run eval v001                             # score against ground truth
```

## The test corpus

Nothing in the tool is state-specific. The schema, the scoring, and the
prompt all speak generic DOT, and handling every state's format is the point
of using a model instead of a hard-coded parser. Accuracy claims, though,
need documents that can be published and re-checked by anyone. Iowa DOT is
one of the few agencies that posts bid tabulations with no login, so the
public test corpus starts there: the
[June 9, 2026 letting](https://iowadot.gov/media/14575/download?inline)
against
[what the agent extracted](https://github.com/brettmboggs/apparent-low/blob/main/results/v001/iowa-2026-06-09.json),
checkable line by line. Most states gate their tabs behind Bid Express or a
plans-room registration until award. Those documents run through the tool the
same way; they just can't be redistributed as test data until sourced
properly. The corpus grows a state at a time, pinned by SHA-256, and every
added state is a test the agent passes or fails in public.
