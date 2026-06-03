# Product Canvas — Notifications Digest Service

> Status: **user-confirmed** (the human customer signed off on this Canvas; it is the
> `user-confirmed` input to the `/agileteam` Phase 0.16 challenge gate). This is a
> seeded fixture for the challenge-gate oracle measurement — neutral by construction
> (see RUNBOOK.md "Leak check").

## Customer

Mid-market SaaS teams (50–500 employees) who already receive a high volume of
in-product and email notifications from our platform: ticket updates, mention alerts,
approval requests, status changes on items they follow.

## Problem (confirmed pain)

These users report being interrupted many times per working day by individual
notifications, each delivered the moment its triggering event occurs. The current
per-event delivery means a single noisy project can generate dozens of separate
emails and in-app banners. Power users have built personal inbox filters to cope, and
several accounts have asked their admins for "a way to receive this less often."
Support tickets reference notification overload as a reason given for disabling
notifications entirely — after which those users miss things that actually mattered.

## Job to be done

"When a lot is happening across the items I follow, help me stay aware of what changed
without having every single change reach me the instant it happens — so I can decide
what to act on at a moment of my choosing instead of being pulled away constantly."

## Proposed solution (the thing under challenge)

A **Notifications Digest Service**: an opt-in delivery mode in which a user's eligible
notifications are accumulated over a recurring window (the user picks daily or weekly,
and a delivery time in their own timezone) and delivered together as a single grouped
digest, instead of one delivery per event. The digest groups related events by the
followed item and by event type, and links each line back to the underlying item.
Time-sensitive notification categories (for example, direct security alerts and
explicit approval requests with a deadline) are explicitly excluded from batching and
continue to deliver immediately.

## Scope (v1)

In scope:
- Per-user opt-in to digest mode, with daily or weekly cadence and a chosen delivery
  time anchored to the user's timezone.
- Accumulation of eligible notifications across the chosen window, grouped by followed
  item and event type, each line deep-linking to the source item.
- A category allowlist/denylist so time-sensitive categories bypass batching.
- A delivery record so a user (and support) can see what was included in a given digest.

Out of scope for v1:
- Machine-learned relevance ranking or prioritization of digest contents.
- Cross-channel delivery beyond the channels notifications already use.
- Per-team or admin-imposed digest policies (this is a per-user opt-in only).
- Real-time "smart" bundling that adapts the window dynamically.

## Success signal (what "this worked" looks like to the customer)

Among users who opt into digest mode, a measurable reduction in the rate at which they
fully disable notifications, with no increase in "I missed something important"
support contacts attributable to delayed delivery. The customer considers the feature
unsuccessful if opted-in users start missing time-sensitive items, or if the digest is
ignored as noise.

## Known constraints / context

- Notifications today are produced by an existing event pipeline and delivered through
  an existing notification queue; the digest mode must consume the same events.
- Users span many timezones; some observe daylight-saving transitions.
- A user can follow a large number of items, and a single window can therefore contain
  a wide range of accumulated events.
- The platform already has the notion of "notification categories"; digest eligibility
  is expressed in terms of those existing categories.

## Open questions the customer left to the build

- Exact default cadence for a newly opted-in user (daily vs weekly) is not yet decided.
- Whether an empty window should send an empty digest or send nothing is undecided.
- How far back a re-tried or delayed digest job may safely look is a build concern, not
  a customer decision.
