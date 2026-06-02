# Changelog

## [0.11.0](https://github.com/DYAI2025/Plumbline/compare/v0.10.1...v0.11.0) (2026-06-02)


### Features

* **cli:** plumbline install subcommand (wraps install.sh) ([a8010a6](https://github.com/DYAI2025/Plumbline/commit/a8010a68954fca13f112e5d7b507bf75fda736d7))
* **cli:** plumbline update (GitHub-release tarball) + plumbline install ([8ee7959](https://github.com/DYAI2025/Plumbline/commit/8ee79591422c1f6d2fe2ce4928c32c65c207e19d))
* **cli:** plumbline update fetches + safely-extracts the latest GitHub release tarball ([21c2515](https://github.com/DYAI2025/Plumbline/commit/21c251592cccad40bd808f52cfd7bb8f4d83cd79))


### Security

* **cli:** `plumbline update` no longer executes a payload-supplied `verifyCommand`; verification runs `--verify-cmd` or the fixed `bash config/claude/tests/run_all.sh`, and the downloaded `compatibility.json` is validated but never `eval`'d ([addf962](https://github.com/DYAI2025/Plumbline/commit/addf9628be09422842211d01db0dd61ce9106b95))
* **cli:** tarball extraction adds the `data` filter (strips setuid/setgid, refuses device/special files) on top of the path-traversal guard, plus download (64 MiB) and extraction (256 MiB) size caps against decompression bombs ([addf962](https://github.com/DYAI2025/Plumbline/commit/addf9628be09422842211d01db0dd61ce9106b95))
* **cli:** release fetch + download are restricted to http(s) and re-validated on every redirect hop, closing an `ftp://`-redirect bypass ([fd2e47e](https://github.com/DYAI2025/Plumbline/commit/fd2e47ed28af170f1c26bf59f031b90f40b6df26))

## [0.10.1](https://github.com/DYAI2025/Plumbline/compare/v0.10.0...v0.10.1) (2026-06-02)


### Bug Fixes

* **tests:** version-agnostic update/release-please tests (un-break main after 0.10.0) ([126d329](https://github.com/DYAI2025/Plumbline/commit/126d3296e71acaa933bea94f9e6b726091af5984))

## [0.10.0](https://github.com/DYAI2025/Plumbline/compare/v0.9.0...v0.10.0) (2026-06-02)


### Features

* add interactive agent collection explorer ([407f49f](https://github.com/DYAI2025/Plumbline/commit/407f49f13f5e4755081289618da1eb28f5b51e1b))
* add release automation and update layer ([d9f9e5a](https://github.com/DYAI2025/Plumbline/commit/d9f9e5a8379c6a3d59709f7e7083b0e750068ffe))
* add release-please automation and plumbline update layer ([5b0f47e](https://github.com/DYAI2025/Plumbline/commit/5b0f47e844421b9f14042f402abab1cb0ab72998))
* **agents:** F2 retro — 4 learned rules ([f53fd64](https://github.com/DYAI2025/Plumbline/commit/f53fd640823ddea6128d2d1de8232e553d7ab705))
* **agents:** F3a retro — 3 learned rules ([fadf266](https://github.com/DYAI2025/Plumbline/commit/fadf266daffc1047715494182c045568d818dd5e))
* **agents:** F3b retro — 4 learned rules ([c6c53aa](https://github.com/DYAI2025/Plumbline/commit/c6c53aafc4d5b086dfbfd86dd0de488f78c89adf))
* **agents:** F3c retro — 4 learned rules ([52eb01c](https://github.com/DYAI2025/Plumbline/commit/52eb01ca1ad9814584ec22f2c8378f02a709cb06))
* **agents:** F3d retro — 2 learned rules ([d380856](https://github.com/DYAI2025/Plumbline/commit/d3808567807de976a25fb4379ed2947f26aef5e0))
* **agileteam:** add mandatory Product Canvas gate before PRD/dev ([62aec4a](https://github.com/DYAI2025/Plumbline/commit/62aec4abcdccd187f9b7c30483f84efa8fb34bdc))
* **agileteam:** add token-bounded council challenge gate (Phase 0.16, mode=challenge) ([fd82dcd](https://github.com/DYAI2025/Plumbline/commit/fd82dcd9ae45e1f2ce05b61990863fa89c522564))
* **agileteam:** add true-line governance and product vision gate ([205ece4](https://github.com/DYAI2025/Plumbline/commit/205ece46839d10186ef505b0f0a20c86e56487f1))
* **agileteam:** CLI iteration counter N/M + per-iteration Kanban view (G7) ([b86f651](https://github.com/DYAI2025/Plumbline/commit/b86f651fbb753f28259012961efd8dba25a52d25))
* **agileteam:** minimum + dynamic team composition (G4) ([115aca5](https://github.com/DYAI2025/Plumbline/commit/115aca5a5972724d5c5f02a2a55a0445f5263c02))
* **agileteam:** per-increment reviewer-&gt;QA-&gt;Watcher chain + graded escalation (G5,G6) ([a122ffa](https://github.com/DYAI2025/Plumbline/commit/a122ffa5b6a853c06a2effd808e843877597e4bb))
* **agileteam:** Vision-GO gate + autonomous /goal handoff (G3) ([8d67c35](https://github.com/DYAI2025/Plumbline/commit/8d67c3529889eb68a815af971408d7fd5e2442e8))
* **concilium:** add /concilium three-body idea+team council (3 new agents) ([6ec98e1](https://github.com/DYAI2025/Plumbline/commit/6ec98e19149b308d7a14eb9bf455d0cf62c70e96))
* **context:** executable resumable run-ledger (resume + human-gate rehash) ([7426c1a](https://github.com/DYAI2025/Plumbline/commit/7426c1af5aa5e36a736f2abc3b14416a3c75c348))
* **install:** auto-register the learning-loop Stop hook ([92de2fb](https://github.com/DYAI2025/Plumbline/commit/92de2fb9cdecd3d53801e816a9c4f1a0aa80763a))
* integrate agileteam v3 — defense-in-depth TDD workflow ([ee77e4c](https://github.com/DYAI2025/Plumbline/commit/ee77e4cd7b8b495f021c51f6fac47162bef10e13))
* **metrics:** rule-ledger provenance (rule_id + approved_at) ([e31fa5e](https://github.com/DYAI2025/Plumbline/commit/e31fa5e8cefe391943e0e0b52647bb6b23fc588b))
* **metrics:** versioned fail-closed contract + cost-per-validated-req emission ([518a4ad](https://github.com/DYAI2025/Plumbline/commit/518a4ad7f2fb52c765d1190cd19c816b57aed6c4))
* **pril:** fail-closed PRIL enforcement Stop hook on git ground-truth ([1ce23f2](https://github.com/DYAI2025/Plumbline/commit/1ce23f2dad36c33d8b4c1dc53fabb9877fdd9c16))
* **pril:** register fail-closed enforce hook (install.sh) + registration test ([9204f64](https://github.com/DYAI2025/Plumbline/commit/9204f6477fe63899473020e27df338a9f9bc9d78))
* real Stop-hook trigger for the agent learning loop ([b73e618](https://github.com/DYAI2025/Plumbline/commit/b73e618f5ae01d04e44a7451659c9bdca9c7395d))
* **reality:** canonical evidence-class crosswalk + vocab-consistency guard test ([45742f0](https://github.com/DYAI2025/Plumbline/commit/45742f005ff0b15987e1c63e7f7f1894813c04c1))
* **reality:** structured pause-reason fields in the true-line gate template ([fec9f44](https://github.com/DYAI2025/Plumbline/commit/fec9f44e259e00810b9538427954f991e9495122))
* vendor agileteam command + agent learning loop protocol ([1a26560](https://github.com/DYAI2025/Plumbline/commit/1a2656032c4fafc78bddc430db98820e9e72c1c2))
* **web:** SessionStart hook so /agileteam works on Claude Code on the web ([d086364](https://github.com/DYAI2025/Plumbline/commit/d086364ab2e7b2bbcce76f163da4276c33161314))


### Bug Fixes

* **agileteam,context-keeper:** actually add G7 M-provenance prose (real fix for b6b55fc) ([06cdba9](https://github.com/DYAI2025/Plumbline/commit/06cdba99d04905fd1fcea312c83b90b1c6a5e1c6))
* **agileteam,context-keeper:** G7 M-provenance — M from planner breakdown, re-scope shown to user (TEST-025h) ([b6b55fc](https://github.com/DYAI2025/Plumbline/commit/b6b55fc629d40cde5045a2edf762a30eab90b08e))
* **agileteam,context-keeper:** M derived from planner breakdown, re-scope shown to user (G7 review) ([6440432](https://github.com/DYAI2025/Plumbline/commit/6440432ff3056da081fc84f5adae3e3985e37032))
* **agileteam,watcher:** re-align is impl-only, Watcher owns unreachable + uncertainty-&gt;user (review) ([80eb711](https://github.com/DYAI2025/Plumbline/commit/80eb711fcbfce8d440cd1aad6ff06c039943de51))
* **agileteam:** complete Canvas traceability + Watcher alignment (patch) ([3578130](https://github.com/DYAI2025/Plumbline/commit/3578130a72ab9d837021b70995c07e053609a270))
* **agileteam:** complete Canvas traceability + Watcher alignment (patch) ([fb812dd](https://github.com/DYAI2025/Plumbline/commit/fb812dd67f95a73eff35dba4dad6db5818c27f51))
* **agileteam:** GO gate reaffirms entry condition; de-tautologize /goal assertion (review) ([3af64d8](https://github.com/DYAI2025/Plumbline/commit/3af64d8683a5cac9c8200a0bf673fed47fbd4951))
* **audit:** repo renamed to Plumbline — update all URLs, bundles to 85, demo count ([8b4042c](https://github.com/DYAI2025/Plumbline/commit/8b4042cfea85cc8ebbf67067c978ffda3f677b4f))
* **ci:** shellcheck clean — SC1003/SC2034/SC2181 ([29854fc](https://github.com/DYAI2025/Plumbline/commit/29854fc1e2b22225a68c63f6468c9043a3e6a516))
* **explorer:** align App.tsx repo label to DYAI2025/Plumbline (source==bundle) ([2bb5e08](https://github.com/DYAI2025/Plumbline/commit/2bb5e083adc880c529f4016794fa5b835a34ebcb))
* **explorer:** exclude concilium/proposed + reports from agent count ([412826a](https://github.com/DYAI2025/Plumbline/commit/412826af607fc4b12958211f74df67b2d33a66fa))
* **explorer:** rebuild bundles to 87 (include plumbline-watcher) ([a644061](https://github.com/DYAI2025/Plumbline/commit/a644061a346bc4d090e5f397b571c340b770edcb))
* install plumbline wrapper libraries ([6128de2](https://github.com/DYAI2025/Plumbline/commit/6128de267d5bd7658840b5e39bac469401316ec8))
* install plumbline wrapper libraries ([be62025](https://github.com/DYAI2025/Plumbline/commit/be620256c0e487d3cb20a1fdf8cf365f7cc83134))
* **metrics:** extend fail-closed validation to values + JSON inputs (review) ([623baa3](https://github.com/DYAI2025/Plumbline/commit/623baa3b2aa59bb6b72d28000d5fed1eab033973))
* **metrics:** resolve config_fingerprint against the Plumbline install (not the target repo) ([dec8372](https://github.com/DYAI2025/Plumbline/commit/dec837259e6062f43be5c3c293315ebb9d71cc22))
* **pril:** close marker-laundering, broad-scope, jq/mktemp fail-open gaps ([8b0b0be](https://github.com/DYAI2025/Plumbline/commit/8b0b0beffe51aa6f64e51182a746ad948d1b9304))
* **pril:** reject glob-class/?-wildcard broad scope patterns (residual H-2) ([276b854](https://github.com/DYAI2025/Plumbline/commit/276b854a3e80218fdd1a53cc7ae7bf3e88ef0334))
* **web:** emit SessionStart reloadSkills + drop set -u in bootstrap hook ([84748c0](https://github.com/DYAI2025/Plumbline/commit/84748c0dd9aa544db586bbf5c4acdab19d694cd8))

## Changelog

All notable changes to this project will be documented in this file.

This file is maintained by release-please from Conventional Commits. Do not hand-edit
release entries.
