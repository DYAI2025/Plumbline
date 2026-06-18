# PRD: OpenRouter Council Backend

Status: user-confirmed
Feature-Slug: openrouter-council-backend
Slice: OD-3
Canvas: docs/canvas/openrouter-council-backend.canvas.md
Vision: docs/vision/openrouter-council-backend.vision.md

> Confirmed by Ben on 2026-06-18 via the `/agileteam` user-confirmation gate.
> M-B-003 resolved: `COUNCIL_4_MODEL` (4 slots, one per council body).

## 1. Summary

Dieses Feature ergänzt `/concilium` um ein optionales OpenRouter-Backend. Die vier
Council-Bodies können über `.env` konfigurierbare Modelle nutzen (ein Slot pro Body). Die
Basisprompts (`concilium/*.md`) bleiben editierbar. Wenn weniger als `COUNCIL_MIN_BACKENDS`
(Default 2) distinkte **normalisierte Basis-Modell-IDs** erreichbar sind, bricht der Council
fail-closed ab.

## 2. Problem Statement

`EXPLICIT`: Council soll die Option auf OpenRouter-Modelle haben.
`EXPLICIT`: Dafür wird ein OpenRouter API Key im `.env` benötigt.
`EXPLICIT`: Council-Modelle sollen als `council_1..4` definierbar sein.
`EXPLICIT`: Basisprompts sollen editierbar bleiben.
`EXPLICIT`: Bei weniger als zwei Backends soll fail-closed gelten.

## 3. Goals

| ID | Goal | Status |
|---|---|---|
| GOAL-B-001 | `/concilium` unterstützt optional OpenRouter. | EXPLICIT |
| GOAL-B-002 | Council-Modelle sind per `.env` konfigurierbar (4 Slots). | EXPLICIT |
| GOAL-B-003 | Prompts pro Council-Rolle bleiben editierbar. | EXPLICIT |
| GOAL-B-004 | `<2` erreichbare unabhängige Modelle führt zum Abbruch. | EXPLICIT |
| GOAL-B-005 | Reports legen verwendete Modelle offen. | ASSUMPTION |
| GOAL-B-006 | Tests laufen ohne echten API-Key. | ASSUMPTION |

## 4. Non-Goals

| ID | Non-Goal |
|---|---|
| NGOAL-B-001 | Kein Commit echter OpenRouter API Keys |
| NGOAL-B-002 | Keine Garantie bestimmter Free-Modelle |
| NGOAL-B-003 | Kein Silent-Fallback auf Claude-only |
| NGOAL-B-004 | Kein automatisches Kosten-/Credit-Management |
| NGOAL-B-005 | Keine vollständige Provider-Abstraktionsplattform über OpenRouter hinaus |

## 5. Functional Requirements

| ID | Requirement | Source | Priority |
|---|---|---|---|
| REQ-B-001 | `/concilium` muss ein optionales OpenRouter-Backend unterstützen. | SRC-B-001, SRC-B-002 | MUST |
| REQ-B-002 | Der OpenRouter API Key muss aus `OPENROUTER_API_KEY` gelesen werden. | SRC-B-003 | MUST |
| REQ-B-003 | `.env` darf echte Keys nicht enthalten, wenn `.env.example` committed wird. | SRC-B-003 | MUST |
| REQ-B-004 | Council-Modellslot 1 muss per `COUNCIL_1_MODEL` konfigurierbar sein. | SRC-B-005, SRC-B-008 | MUST |
| REQ-B-005 | Council-Modellslot 2 muss per `COUNCIL_2_MODEL` konfigurierbar sein. | SRC-B-005, SRC-B-008 | MUST |
| REQ-B-006 | Council-Modellslot 3 muss per `COUNCIL_3_MODEL` konfigurierbar sein. | SRC-B-005, SRC-B-008 | MUST |
| REQ-B-006b | Council-Modellslot 4 muss per `COUNCIL_4_MODEL` konfigurierbar sein (M-B-003 resolved). | User 2026-06-18 | MUST |
| REQ-B-007 | Lowercase Aliase `council_1..4` sollen optional unterstützt werden. | SRC-B-005, SRC-B-008 | SHOULD |
| REQ-B-008 | Uppercase Env-Werte sollen Vorrang vor lowercase Alias-Werten haben. | SRC-B-008 | SHOULD |
| REQ-B-009 | Free OpenRouter-Modelle sollen konfigurierbar sein, aber nicht als feste Liste hart verdrahtet werden. | SRC-B-004, SRC-B-010 | SHOULD |
| REQ-B-010 | Basisprompts pro Council-Rolle müssen aus editierbaren Dateien (`concilium/*.md`) geladen werden. | SRC-B-006 | MUST |
| REQ-B-011 | Der Council muss prüfen, ob mindestens `COUNCIL_MIN_BACKENDS` (Default 2) **distinkte normalisierte Basis-Modell-IDs** erreichbar/verwendbar sind. Diversität wird auf der normalisierten Basis-Modell-Identität gemessen: bekannte Variant-/Preis-/Provider-Suffixe (`:nitro`, `:floor`, `:exacto` und jedes `:<variant>`-Suffix) werden vor dem Vergleich entfernt, sodass zwei Variant-IDs desselben Basis-Modells als EIN Modell zählen. Gezählt werden distinkte normalisierte Basis-Slugs, nicht rohe ID-Strings. Die Bedeutung von „erreichbar/verwendbar" ist an OQ-B-004 gebunden (Methode + `erreichbar ≠ invocable`, impl-verifiziert) und bis dahin `ungeprüft`. | SRC-B-007 | MUST |
| REQ-B-012 | Bei `<COUNCIL_MIN_BACKENDS` (Default 2) erreichbaren distinkten normalisierten Basis-Modell-IDs muss `/concilium` mit `COUNCIL_DIVERSITY_UNAVAILABLE` abbrechen. | SRC-B-007 | MUST |
| REQ-B-013 | Es darf keinen stillen Fallback auf Claude-only geben, solange Fail-Closed aktiv ist. | SRC-B-007 | MUST |
| REQ-B-014 | Jeder Council-Report muss pro Rolle die verwendete Modell-ID nennen. | SRC-B-009 | SHOULD |
| REQ-B-015 | Tests müssen ohne Netzwerk und ohne echten API-Key laufen. | SRC-B-009 | MUST |

## 6. Non-Functional / Security Requirements

| ID | Requirement | Source | Priority |
|---|---|---|---|
| REQ-B-016 | API Keys dürfen nie in Logs, Reports, Snapshots oder Testausgaben erscheinen. | SRC-B-003 | MUST |
| REQ-B-017 | Netzwerkfehler müssen als Council-Unverfügbarkeit berichtet werden, nicht als erfolgreiche Council-Ausführung. | SRC-B-007 | MUST |
| REQ-B-018 | Timeout muss konfigurierbar sein. | ASSUMPTION | SHOULD |
| REQ-B-019 | Promptquellen müssen im Report nachvollziehbar sein. | SRC-B-006 | SHOULD |
| REQ-B-020 | Die Implementierung muss Feature-Flag-/Backend-gesteuert sein, damit bestehende Claude-only-Flows nicht unklar überschrieben werden. | ASSUMPTION | SHOULD |

## 7. Proposed `.env.example`

```dotenv
# OpenRouter Council Backend
# Never commit real secrets in .env.example.

COUNCIL_BACKEND=mock
COUNCIL_FAIL_CLOSED=true
COUNCIL_MIN_BACKENDS=2
COUNCIL_TIMEOUT_SECONDS=45

OPENROUTER_API_KEY=
OPENROUTER_HTTP_REFERER=
OPENROUTER_APP_TITLE=Plumbline

# One slot per council body (market-realist, tech-arbiter, skeptic, distribution-realist).
COUNCIL_1_MODEL=
COUNCIL_2_MODEL=
COUNCIL_3_MODEL=
COUNCIL_4_MODEL=

# Optional lowercase aliases for user convenience. Canonical names are uppercase.
council_1=
council_2=
council_3=
council_4=
```

## 8. Acceptance Criteria

### AC-B-001: Config Loading
Given `.env` contains `COUNCIL_1_MODEL`..`COUNCIL_4_MODEL`
When the Council config loader runs
Then it returns four configured model slots without exposing `OPENROUTER_API_KEY`

### AC-B-002: Lowercase Alias Support
Given `.env` contains `council_1`..`council_4` and uppercase variants are empty
When the config loader runs
Then it maps lowercase values into the corresponding Council slots

### AC-B-003: Uppercase Precedence
Given both `COUNCIL_1_MODEL` and `council_1` exist
When the config loader runs
Then `COUNCIL_1_MODEL` wins

### AC-B-004: Fail-Closed with Zero Models
Given OpenRouter validation returns zero reachable configured models
When `/concilium` starts with `COUNCIL_FAIL_CLOSED=true`
Then it aborts with `COUNCIL_DIVERSITY_UNAVAILABLE`

### AC-B-005: Fail-Closed with One Model
Given OpenRouter validation returns one reachable configured model
When `/concilium` starts with `COUNCIL_FAIL_CLOSED=true`
Then it aborts with `COUNCIL_DIVERSITY_UNAVAILABLE`

### AC-B-006: Minimum Diversity Pass
Given OpenRouter validation returns at least `COUNCIL_MIN_BACKENDS` (default 2) distinct reachable model IDs **after normalization to base-model identity** (variant/price/provider suffixes such as `:nitro`/`:floor`/`:exacto`/`:<variant>` stripped before counting)
When `/concilium` starts
Then the Council may proceed and assigns roles to configured models

### AC-B-007: Prompt Editability
Given a Council role prompt file (`concilium/<body>.md`) is edited
When `/concilium` loads that role
Then it uses the edited prompt content

### AC-B-008: Model Disclosure
Given `/concilium` completes with OpenRouter backend
When the report is generated
Then the report includes role name, model ID, backend name and prompt source

### AC-B-009: Secret Redaction
Given `OPENROUTER_API_KEY` is set
When config, errors or reports are printed
Then the raw key never appears

### AC-B-010: No Silent Fallback
Given OpenRouter fails validation and `COUNCIL_FAIL_CLOSED=true`
When `/concilium` runs
Then it does not continue as Claude-only unless the user explicitly configured non-fail-closed behavior

## 9. Evidence Requirements

| ID | Evidence | Required For |
|---|---|---|
| EV-B-001 | Config loader test output | REQ-B-002 bis REQ-B-008 (inkl. 006b) |
| EV-B-002 | Fail-closed test output | REQ-B-011 bis REQ-B-013 |
| EV-B-003 | Redaction test output | REQ-B-016 |
| EV-B-004 | Prompt loader test output | REQ-B-010, REQ-B-019 |
| EV-B-005 | Report snapshot | REQ-B-014 |
| EV-B-006 | `.env.example` review | REQ-B-003 |
| EV-B-007 | Optional real-boundary smoke (fake-safe key handling) | future validation only |

## 10. Risks and Edge Cases

| ID | Edge Case | Expected Behavior |
|---|---|---|
| EDGE-B-001 | `OPENROUTER_API_KEY` missing and backend=openrouter | fail-closed with missing-secret message, no raw env dump |
| EDGE-B-002 | Same base model in all slots (incl. distinct variant-IDs of the same base, e.g. `:nitro` vs `:floor`) | normalize to base-model identity → counts as 1 distinct model → fail-closed with `COUNCIL_DIVERSITY_UNAVAILABLE` |
| EDGE-B-003 | Free model unavailable | fail-closed with a `model-unavailable` classified message |
| EDGE-B-004 | OpenRouter timeout | fail-closed with timeout classification |
| EDGE-B-005 | Prompt file missing | fail-closed with a `prompt-missing` classified error |
| EDGE-B-006 | One role has no assigned model | fail-closed with a `model-unconfigured` classified configuration error |
| EDGE-B-007 | User sets Claude-only intentionally | allowed only with clear disclosure and fail-closed override if policy permits |

## 11. Implementation Notes

- Keine echten Free-Modell-IDs als stabile Wahrheit hardcoden.
- Fake-Transport/Fixtures für Tests; kein Netzwerk, kein echter Key.
- Canonical uppercase Env-Namen; lowercase Aliase = Kompatibilität.
- Niemals `OPENROUTER_API_KEY` roh ausgeben.
- Tatsächlich genutzte Modell-IDs reporten.
- OpenRouter-Verfügbarkeit = Runtime-Evidenz, nicht statische Wahrheit.
- **Kanonische Fallback-Regel (N1, kein Widerspruch):** Es gibt **keinen stillen** Fallback auf
  Claude-only (REQ-B-013 / NGOAL-B-003). Ein vom User **explizit** konfigurierter Claude-only-Modus
  ist erlaubt — aber nur mit Disclosure und nicht still (EDGE-B-007 / AC-B-010). „Kein stiller Fallback"
  und „explizit konfigurierter Claude-only mit Disclosure" sind damit dieselbe Regel aus zwei Richtungen,
  kein Konflikt.
- **Reality Ledger:** Fake-Transport-Tests bleiben `integration-fake`; der „echte Diversität"-Claim
  bleibt RED, bis ein optionaler Real-Boundary-Smoke (außerhalb Repo/Tests) ihn stützt.
- **Limitation Diversitäts-Gate (notwendig, nicht hinreichend):** Basis-Slug-Normalisierung
  (Strippen von `:nitro`/`:floor`/`:exacto`/`:<variant>`) schließt das offensichtliche Aliasing-Loch
  — zwei Variant-IDs desselben Basis-Modells zählen als EIN Modell. Sie kann aber **nicht** beweisen,
  dass zwei genuin unterschiedliche Slugs nicht doch dasselbe oder ein sehr ähnliches Modell sind
  (Provider-Routing-Aliase, umbenannte/gespiegelte Modelle). Das Gate **reduziert** Schein-Diversität,
  es **eliminiert** sie nicht. Reale Modell-Diversität bleibt konsistent mit dem Reality Ledger
  RED(confidence), bis ein Real-Boundary-Smoke sie stützt.
- **Reachability ist eine ungeprüfte externe-API-Prämisse (`ungeprüft`, siehe OQ-B-004):** Die
  Reachability-Check-METHODE (Katalog/list-models vs. eine Probe-Completion) und die Unterscheidung
  **`erreichbar ≠ invocable`** (ein gelistetes Modell kann für den Key/das Guthaben des Users trotzdem
  402/429 liefern) sind zur Implementierungszeit gegen die **live OpenRouter API** zu verifizieren. Der
  Coder darf keine einzelne unverifizierte Definition still festschreiben; bis zur Impl-Verifikation bleibt
  diese Prämisse `ungeprüft`. REQ-B-011 ist an OQ-B-004 gebunden.

## 12. Definition of Done

- Alle MUST-Requirements (inkl. REQ-B-006b) erfüllt.
- Config-, Fail-Closed-, Redaction-, Prompt-Loader- und Disclosure-Tests grün.
- `.env.example` aktualisiert (4 Slots).
- `/concilium`-Dokumentation aktualisiert.
- OpenRouter-Fehler kann sich nicht als erfolgreicher diverser Council ausgeben.
- User Confirmation liegt vor (Ben, 2026-06-18). ✔

## Spec remediation (2026-06-18)

Targeted remediation of the Phase-0.5 spec-auditor BLOCKER (user decision: "Strengthen + document").
No scope expansion, no new YAML frontmatter.

- **B1 (BLOCKER, diversity Goodhart proxy):**
  - Strengthened: REQ-B-011/REQ-B-012 and AC-B-006 now measure diversity on the **normalized
    base-model identity** — variant/price/provider suffixes (`:nitro`/`:floor`/`:exacto`/`:<variant>`)
    are stripped, count is of distinct normalized base slugs (not raw ID strings). EDGE-B-002 updated:
    same base model across slots → counts as 1 → fail-closed. Summary §1 aligned.
  - Documented limitation: §11 + canvas Risks now state base-slug normalization is **necessary,
    not sufficient** — it reduces but does not eliminate Schein-Diversität; real diversity stays
    RED(confidence) per the Reality Ledger.
  - Overclaim fix (I3): Vision Statement/Value Proposition and canvas Value Proposition no longer
    assert unqualified „echte Modell-Diversität / real diversity"; replaced with „reduzierte
    Backend-Monokultur / geringere Modellkorrelation, ≥2 distinkte normalisierte Basis-Modelle als
    notwendige, nicht hinreichende Bedingung".
- **B2 (BLOCKER, unverified reachability premise):** canvas OQ-B-004 generalized to all reachability;
  §11 note added — reachability METHOD (catalog/list-models vs. probe completion) and
  `erreichbar ≠ invocable` (402/429 for the user's key/credits) are to be verified at implementation
  against the live OpenRouter API. REQ-B-011's „erreichbar/verwendbar" bound to OQ-B-004; premise
  marked `ungeprüft` until impl-verified.
- **I2 (important, disjunctive expected behaviors):** EDGE-B-003/EDGE-B-005/EDGE-B-006 collapsed from
  "fail-closed OR …" into single deterministic fail-closed outcomes with specific classified messages
  (`model-unavailable` / `prompt-missing` / `model-unconfigured`).
- **Minor N2:** REQ-B-011/REQ-B-012 and AC-B-006 now reference the configured `COUNCIL_MIN_BACKENDS`
  (default 2) instead of hardcoding "two", consistent with `.env.example`. AC-B-004 (0 models) and
  AC-B-005 (1 model) remain valid deterministic sub-cases of `<COUNCIL_MIN_BACKENDS` at the default.
- **Minor N1:** Added one canonical fallback-rule statement (§11) reconciling „kein stiller Fallback"
  (REQ-B-013/NGOAL-B-003) with „explizit konfigurierter Claude-only mit Disclosure" (EDGE-B-007/AC-B-010).

REQ ↔ AC ↔ Vision remain internally consistent. **Spec is ready to re-freeze pending user
confirmation at the gate** (Status lines left unchanged; user re-confirms at the gate).
