---
title: 'Session prompting'
description: 'An agent that inherits the clearance of the person asking, and never has one of its own.'
date: 2026-08-26
tags: ['datum', 'decision log']
draft: false
unlisted: true
---

<!--
DRAFT for Brett's review. Sourced from datum-core: ai/tenantScope.ts,
ai/sqlGuard.ts, ai/dataPolicy.ts, ai/dbTools.ts, ai/aiGuardrails.ts,
ai/spendGuard.ts, agent_framework + memory migrations, tenant-zero audit
phase 10/13. Stays draft: true until Brett approves item by item.
-->

## The decision

Datum's assistant can read the tenant's live database. Not a curated snapshot,
not five numbers injected into a prompt: it lists tables, reads columns, and
writes its own bounded SELECTs against production. The design rule that makes
this survivable is one line. The assistant inherits the clearance of the person
asking, and never has one of its own. Every tool closes over the verified
tenant and the caller's role at session start; nothing about either is taken
from model output.

The first version was the cautious alternative, and it failed in the honest
way: a fixed handful of COUNT(*) probes in the system prompt, so any question
outside those numbers got a roundabout non-answer telling the user to go look
it up themselves. My co-founder's complaint from that era is preserved
verbatim in the code comments. The other alternative was trusting the prompt:
tell the model to filter by tenant and behave. A system prompt that asks a
model nicely not to read a table is a suggestion, not a wall.

## The walls

Model-authored SQL passes through guards enforced in code, never in the prompt.
One proves a statement cannot write: single statement, no comments, read-only
shape, keyword and table denylists, row cap. One proves it cannot read across
tenants: every tenant-keyed table referenced must carry its own tenant
predicate bound to the session's parameters, and unknown tables are treated as
tenant-keyed by default, so a table added tomorrow is protected before anyone
updates a list. A data policy layer separates read-only from need-to-know: a
foreman asking a colleague's salary is refused for the same reason he would be
refused in the HR office, while craft rates stay open to anyone who prices
work, because a laborer's hourly cost is costing data, not somebody's private
business. When a guard refuses, it says so plainly. It never quietly returns
something adjacent, because a user told "there's no such data" learns the
wrong thing about their own company.

Around the loop sit operational guards: a per-tenant kill switch, a monthly
spend cap, and role gating, enforced inside the provider so background jobs
cannot bypass them. Agents run from a registry with per-agent tool grants and
persistent, tenant-scoped memory, inside the same row-level security boundary
as every human request. Every statement runs with a five-second lock timeout,
because the assistant shares a database with people doing real work, and an AI
query must never hold a lock a foreman is waiting on.

## What broke

The tenant-zero audit attacked the guards directly, and phase 10 won four
times. `WHERE TenantId = @t OR 1=1` disjoined the tenant predicate. A
predicate wrapped in parentheses counted as coverage when it should not have.
A scoped first UNION branch vouched for an unscoped second one. Each shape was
proven returning the anchor tenant's rows to another tenant, then structurally
refused: top-level ORs rejected outright, parenthesized predicates no longer
count, every set-operator branch checked independently. The guard's own
comments admit what it is, regex analysis rather than a SQL parser, which is
exactly why database-enforced RLS now sits underneath it as the layer that
does not care how clever the SQL is.

The payroll lesson came separately. Read-only felt safe until it was pointed
out that within one tenant, read-only still meant any user with a chat window
could ask what a named person earns and get a real number off a real row.
Read-only is not the same as need-to-know. That distinction is now the data
policy layer.

## Where it stands

Strict default-deny costs something: a new genuinely-global table gets refused
until it is registered, and the model burns a correction round-trip when a
guard rejects its SQL. Both are prices worth paying, because the error text
teaches the model to self-correct and the refusal fails safe. The prompt is
still carefully written. It is just not load-bearing. Everything that matters
is enforced by something that cannot be talked out of it.
