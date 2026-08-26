---
title: 'Session prompting'
description: 'Designing the agent layer to live inside the tenant boundary.'
date: 2026-08-26
tags: ['datum', 'decision log']
draft: true
---

<!--
DECISION LOG TEMPLATE. Stays draft: true until Brett fills the TODOs with the
real design story and numbers. Same shape as tenant-isolation.md: chose X
over Y, cost Z, what broke. No em-dashes. Stoic and concrete.
-->

## The decision

The agent layer runs inside the same boundary as everything else: a tool registry and
persistent memory fenced by SQL guardrails and data policy, so an agent cannot reach across
tenants.

TODO: one paragraph on how session prompting is actually designed. What the alternatives
were (one big prompt, per-feature prompts, something else), and what forced the choice.

## Why not the other way

TODO: the honest case for the design not taken, and the specific reason it lost.

## What it cost

TODO: the price paid. Token budgets, latency, the places the guardrails made simple
things harder. Real numbers where they exist.

## What broke

TODO: the prompt injection attempt, the runaway session, or the near miss that
stress-tested the design, and what changed after.

## Where it stands

TODO: would the same choice win today. One paragraph.
