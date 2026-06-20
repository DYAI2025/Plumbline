# OpenRouter Council-Runner GUI — Live Real-Boundary Smoke (2026-06-20)

Slice 4 `openrouter-gui`, REQ-GUI-001 / AC-LIVE. A **real captured live run** through the GUI
against OpenRouter — NOT a fabricated snapshot, and NOT a demo (the bundled demo was removed
per the user's no-fake override: "nur echt und nur was geht. Fake=Demo, dann weglassen"). The
API key was loaded server-side from `~/.openclaw/.env`, passed ONLY to the subprocess child env,
used only in the council's `Authorization` header, and is **never** in this trace
(leak-check = 0 in both the HTTP response and the server log).

## Command (the real served path)
```
# COUNCIL_INFERENCE_LIVE=1, key resident server-side (never printed)
$ python3 config/claude/gui/openrouter_gui_proxy.py serve --bind 127.0.0.1 --port <p>
# then over the loopback socket:
POST /run  {"subject":"Add a Redis cache in front of the user-profile DB read path.",
            "preset":"A","mode":"live"}
```
The proxy shelled out to the frozen `deepseek_review.py preset --live --json` (the vetted council
primitive); the key reached only the child env. No demo, no fake fallback.

## Captured result

| Field | Value |
|---|---|
| HTTP status | **200** |
| overall code | `COUNCIL_MODEL_UNAVAILABLE` (mixed: 1 OK role, 3 failed — surfaced honestly) |
| diversity | distinct_bases **4**, gate `COUNCIL_DIVERSITY_OK` |
| secret leak-check | **0** (response body + server log) |

| Role | Model (free) | Result |
|---|---|---|
| Visionaerin | `qwen/qwen3-coder:free` | `COUNCIL_RATE_LIMITED` |
| Pruefer | `cognitivecomputations/dolphin-mistral-24b-venice-edition:free` | `COUNCIL_RATE_LIMITED` |
| Nutzeranwalt | `cohere/north-mini-code:free` | `COUNCIL_MODEL_UNAVAILABLE` |
| **Macherin** | **`google/gemma-4-26b-a4b-it:free`** | **`COUNCIL_INFERENCE_OK` — a real 907-char council position** |

## What this proves (real-boundary-smoke) — and what it does NOT
| Claim | Evidence class | Status |
|---|---|---|
| The GUI crosses the REAL OpenRouter boundary and renders a REAL free-council position through the served `POST /run` path (no demo, no fake) | **real-boundary-smoke** | proven (1 real position rendered live) |
| Per-role attrition (rate-limit / unavailable) is surfaced HONESTLY, classified, never hidden or faked into a success | **real-boundary-smoke** | proven (3/4 classified failures shown; overall honestly `COUNCIL_MODEL_UNAVAILABLE`) |
| The key never leaves the server (child-env only) — absent from the response + log on a live mixed-result run | verified | leak-check 0 |
| The free council is "good" / catches more / is a usable everyday tool | — | **NOT CLAIMED** — this is a wiring/capability smoke, not a value or quality verdict |

## Honest finding (the free-tier reality, shown not hidden)
This run hit **3/4 attrition** — the same free-tier rate-limit reality measured in EXP-009. The GUI
delivered exactly **what actually works** (one real position from `gemma-4-26b:free`) and honestly
classified the rest, with no fabricated fallback. The council's per-role model selection comes from
the frozen resolver (`council_presets.FREE_MODEL_FAMILY_PREFERENCE`, byte-unchanged), which on the
current catalog resolves `qwen3-coder` + free-route picks; a future slice could update that
preference to prefer the stronger reachable free families (e.g. `gemma`/`gpt-oss`/`nemotron`, per
EXP-009) — but that edits the frozen substrate and is out of this slice.

## Honest ceiling
A single live smoke proving the served path crosses the real boundary and renders real positions +
honest attrition with no key leak. It is NOT a measurement of council quality or a usability verdict,
and free-tier reachability is intermittent (a re-run may show different per-role attrition). The
RISK-B-007 disclosure (distinct ids != proven cognitive diversity) is rendered in the UI beside the
diversity block.
