---
title: 'Tenant isolation'
description: 'App-layer scoping, an adversarial audit, and the day RLS went under all of it.'
date: 2026-08-26
tags: ['datum', 'decision log']
draft: false
unlisted: true
---

<!--
DRAFT for Brett's review. Every fact below is sourced from datum-core:
docs/audit/tenant-zero/REPORT.md, docs/notes/TENANT_ISOLATION_RLS_PLAN.md,
SECURITY.md, src/lib/tenantScopedDb.ts, migrations. Nothing invented.
Stays draft: true until Brett approves item by item.
-->

## The decision

Datum is one shared platform for construction companies that are sometimes
competitors bidding the same lettings. Isolation started as an application-layer
rule: every query carries the tenant of the verified Entra ID principal, and
role based access resolves from the directory claim. There were three real
options. A database per tenant was the safest on paper and lost on operations:
one engineer, 900-plus tables, 500-plus migrations, and cross-tenant features
like two bidders on one public letting that a per-tenant split makes painful.
SQL Row-Level Security was the airtight option and lost at first for a quieter
reason: the schema was changing daily, and RLS on a pooled connection needs
per-connection session context that is easy to get subtly wrong. Half-applied
RLS is worse than none, because it looks like a wall. So the app layer went
first, with the discipline that every tenant-keyed table gets its own WHERE
clause.

## Why not the other way

The honest case for RLS from day one is that an app-layer rule relies on nobody
ever forgetting it. That case eventually won. What it took to win is the rest
of this page.

## What broke

Before taking a second paying customer, I ran a tenant rehearsal audit: a
disposable copy of production, four synthetic construction companies provisioned
through the real product endpoints, then used to attack each other and the
anchor tenant across 101 phases. It found what an attacker would have found.
One company could overwrite another's payroll. When the platform could not tell
who was signing in after a cold start, it guessed the anchor tenant, and an
unidentifiable sign-in was handed 38 of that tenant's projects. A brand-new
customer could read another company's medical-leave records. Approvals passed
when nobody held the approving role. Twenty-six endpoints reported "saved"
while silently dropping fields, including a subcontract value and an invoice
total.

Thirteen fixes merged and went live within days, each re-proven by a probe
rather than by reading the diff. Then an independent review re-ran the evidence
and found the audit's own blind spot: every defect class the fixes closed was
still alive somewhere the detectors never looked. Fixing sites is not fixing
classes. That sentence is what ended the app-layer-only era.

## The reversal

The missing-WHERE-clause leak is a class, and the only structural answer is the
database refusing. The RLS program shipped in one day: five PRs, four
migrations, 852 tables under fail-closed FILTER and BLOCK policies keyed to
SESSION_CONTEXT. Fail-closed means a query that never set its tenant context
sees zero rows and writes none. Context is set in the same batch as the
statement, because pooled connections are reused across tenants and a context
set in one round trip can land on a different physical connection in the next.
Employees alone had 191 query sites, so call-site conversion would never have
finished; instead a hook runs every HTTP handler inside an AsyncLocalStorage
tenant scope and the pool wrapper primes context on every query automatically.
Twenty-nine background timers got wrapped the same way. Tenant columns went
NOT NULL with deliberately no default, so an unstamped insert refuses instead
of silently becoming the anchor tenant's.

Verification was observational, never "the code looks right": with no context,
reads return zero rows against tables holding tens of thousands of live records;
forty concurrent alternating-tenant queries showed zero bleed-through; a
deliberately WHERE-less query still came back tenant-scoped.

## Where it stands

Four layers, each assuming the one above it failed: the verified principal, the
app-layer WHERE clause, RLS underneath it, and a build-failing lint that refuses
any new table that has not declared its tenancy. The lint caught an unregistered
table within weeks, with no human memory involved. Would the same path win
again? I would still ship the app layer first. I would run the rehearsal audit
before the first customer instead of before the second, and turn RLS on while
the tables were still empty.
