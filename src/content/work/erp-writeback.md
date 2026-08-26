---
title: 'ERP writeback'
description: 'A durable queue between the platform and the accounting systems contractors already run.'
date: 2026-08-26
tags: ['datum', 'decision log']
draft: true
---

<!--
DECISION LOG TEMPLATE. Stays draft: true until Brett fills the TODOs with the
real integration war stories. Same shape as tenant-isolation.md: chose X over
Y, cost Z, what broke. No em-dashes. Stoic and concrete.
-->

## The decision

An ERP adapter framework with a durable writeback queue, normalizing phase codes and cost
types, so the platform talks to the accounting systems contractors already run.

TODO: one paragraph on the fork. Direct synchronous writes versus a durable queue versus
one-way import only, and what forced the choice.

## Why not the other way

TODO: the honest case for synchronous writes or import-only, and the specific reason each lost.

## What it cost

TODO: the price paid. The queue's own failure modes, reconciliation work, the mapping tables
for phase codes and cost types. Real numbers where they exist.

## What broke

TODO: the writeback that failed, the double-post, or the mapping that went sideways, and
what changed after.

## Where it stands

TODO: would the same choice win today. One paragraph.
