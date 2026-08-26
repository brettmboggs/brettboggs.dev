---
title: 'Tenant isolation'
description: 'Query-layer isolation over RLS, and what it cost.'
date: 2026-08-26
tags: ['datum', 'decision log']
draft: true
---

<!--
DECISION LOG TEMPLATE. Stays draft: true until Brett fills the TODOs with the
real numbers and war stories. Senior readers skim these for judgment, not
feature lists: chose X over Y, cost Z, here is what broke. Copy this file for
the other logs (RLS vs app layer detail, session prompting design). No
em-dashes. Keep the voice stoic and concrete.
-->

## The decision

Tenant isolation is enforced at the query layer rather than trusted to callers, with role based
access through Entra ID.

TODO: one paragraph on the fork in the road. What were the two or three real options
(SQL RLS, app-layer filtering, separate databases per tenant), and what forced a choice.

## Why not the other way

TODO: the honest case for the road not taken, and the specific reason it lost.

## What it cost

TODO: the price paid. Migration effort, query overhead, the places it made simple things
harder. Real numbers where they exist.

## What broke

TODO: the incident or near miss that stress-tested the decision, and what changed after.

## Where it stands

TODO: would the same choice win today. One paragraph.
