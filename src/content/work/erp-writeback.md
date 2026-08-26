---
title: 'ERP writeback'
description: 'The decision was who owns the money. The queue is just the consequence.'
date: 2026-08-26
tags: ['datum', 'decision log']
draft: false
unlisted: true
---

<!--
DRAFT for Brett's review. Sourced from datum-core: docs/DATUM_E2_ERP_PLAN.md,
docs/notes/SPECTRUM_REWRITE_DESIGN.md, docs/notes/QUANTITY_PIPELINE_DESIGN.md,
services/erp/*, migration 2026_06_11_06, commits 0ccda34 / fd17f20 / 7610c26,
BLAKE_NOTES_2026-08-02. Verified: 8 cost types (never say 142), 396 MW cost
codes, 109 queued rows, 171 jobs in the fixture incident.
Stays draft: true until Brett approves item by item.
-->

## The decision

The fork everyone expects here is synchronous writes versus a queue versus
import-only. That was not the real fork. The real decision was who owns the
money, and it got settled early: the accounting system contractors already run
is the source of truth for actuals. Datum creates the records, exports them,
and reads the real numbers back. Datum owns creation, estimates, and
projections. The ERP owns job-to-date, billed, invoiced, and committed. Datum
never computes actuals by summing its own rows, because two systems that each
believe they hold the ledger will eventually disagree, and a construction
company settles that argument in favor of accounting every time.

The business problem underneath was stated by my co-founder in one line:
quantities were being entered two and three times across systems. So the
pipeline runs one direction: a foreman's timecard quantities carry through to
month-close, a PM verifies them, and the verified intent is queued for the ERP.

## Why a queue

Because the destination did not exist yet. Integration credentials for the
customer's ERP were months away, and a synchronous write would have had two
options while waiting: fail the PM's month-close, or silently drop the export.
Both are wrong. The durable queue holds every verified intent, visibly labeled
as awaiting the ERP connection, never silently dropped. When credentials land,
the wiring is mechanical.

The queue is boring on purpose: SQL-backed, retry with exponential backoff at
one, five, fifteen, sixty, then two hundred forty minutes, five attempts before
a row parks as failed with its error message and an admin retry button.
Enqueue is idempotent on tenant, resource type, and resource id, keyed for
quantities as project by month by cost code, so a double-click cannot double-
queue an intent. Re-opening a verified month recalls its queued intents, with
one carve-out written into the code: a write that already reached the adapter
is a fact, not an intent, and facts do not get recalled. Every boundary
crossing lands in an append-only sync log. The retry policy is extracted as a
pure function under unit test, because a wrong exhaustion decision either
spams an accounting system or silently gives up on posting real money.

The non-negotiable rule for the day writes go live is the double-post story:
an ambiguous failure, a timeout after the vendor committed, must not post
twice. Every write carries Datum's resource id as the vendor-side reference,
and where the vendor cannot store one, the adapter does a check-before-create
read on any retry. No write ships without that story written down.

Normalization is per-tenant configuration, not code: each tenant declares its
phase-code segment layout and its cost-type map, eight single-letter codes for
the anchor tenant, and an unmapped code passes through labeled rather than
breaking the response.

## What broke

The worst incident came from the safety apparatus, not the risky part. To
build against an ERP with no credentials, a mock adapter serves hand-written
fixtures: one invented job with invented contract, cost, and billing figures.
Nothing distinguished "developer wants fixtures" from "no ERP is connected,"
so every deployed project page dressed those fixtures up as that job's
financials. One hundred seventy-one live jobs showed the same fake $850K.
The fix drew the line the design had skipped: fixtures render only where
fixtures are asked for, and a disconnected ERP now says so instead of
inventing a number.

The fix caused its own smaller lesson. Disconnected endpoints first returned
503, which was the right answer in the wrong tone: healthy screens full of red
"Service Unavailable" in the console, and a platform error-rate chart carrying
constant noise from a feature that simply was not switched on, which is
exactly how a real failure gets lost. They now return a calm 200 with a
not-connected code.

## Where it stands

Honestly: the seam is built and the connection is not. The queue holds over a
hundred verified month-close intents accumulated in production, deliberately,
while write-enablement stays off and the real adapter waits on vendor
credentials. Reads run end to end against the mock. Reconciliation is designed
but not built, and its central rule is already fixed: Datum legitimately runs
ahead of the ERP, and where the two disagree on a posted value, the ERP wins
and Datum's row is flagged for a human, never silently overwritten. Would the
queue win again? Yes, and earlier. It let the product ship real capture and
verification months before the integration it feeds, and the backlog it
accumulated is not debt. It is the export, waiting.
