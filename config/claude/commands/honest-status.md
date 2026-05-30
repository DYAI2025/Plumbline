---
description: Give an honest status of the current work — what was actually done, hoped-for vs. real result, and what was missed or remains unproven. The plumb line for your own progress. Use when the user asks "what did you do / how well did it go / what's the status", before continuing a long task, or whenever a claim of done-ness needs to hang true.
---

You are running the **honest-status** check — Plumbline's *"does it hang true?"*
applied to your own work. The point is to separate *looks done* from *is done*, in
plain language, including the uncomfortable parts. No marketing, no hedging-to-impress.

## When to use
- The user asks some form of: "what exactly are you doing / what was built / how well
  did the goals get hit / what was missed?"
- Before continuing an expensive or long-running task (checkpoint the truth first).
- Before any "it works / it's done / it's shipped" claim leaves your mouth.

## Output (terse, in the user's language; default German if they wrote German)

1. **Was ich tue / getan habe** — one or two sentences, concrete, no jargon.
2. **Erhofftes Ergebnis** — what this was *supposed* to achieve.
3. **Reales Ergebnis** — what the evidence actually shows. Cite the evidence
   (command output, test result, file, log) — not your memory of it.
4. **Verfehlt / ungeprüft** — what did NOT work, what is `*-fake` / not wired into
   production / not yet verified, and what you are *assuming* rather than knowing.
   This section is mandatory and must not be empty unless everything is genuinely
   verified — say so explicitly if so.
5. **Nächster ehrlicher Schritt** — the one action that would most reduce remaining
   uncertainty.

## Guardrails (learned from this project)
- **Tests green ≠ it works.** A passing suite against a fake/mock is *not* evidence the
  real boundary works. If the capability touches I/O, a remote, an external API/SDK or
  the production composition root, and you have not exercised the *real* path, label it
  **unverified** — do not report it as done.
- **Verify before claiming.** Prefer running the thing and quoting its output over
  asserting an outcome. If you cannot verify, say "unverified" and why.
- **Surface the dark zone.** The most load-bearing failure is usually the one nobody is
  looking at ("exists in tests, never composed in prod"). Name it even if unasked.
- **Distinguish knowledge from inference.** Claims about foreign code, external state,
  versions, numbers, dates — mark as verified, inferred, or unverified. Never launder
  an unverified claim into a confident statement.
- **No silent self-downgrade of a red flag.** If you found a "not wired / not real"
  problem, only the user reclassifies it — you report it, every time.

This check is cheap and should add near-zero overhead. Its value is precisely on the
days the honest answer is *"less than it looks."*
