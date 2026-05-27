# Agent Collection Explorer — source

Source for the interactive explorer bundled to `../agent-explorer.html`.

These files are an **overlay** on the project the
[`artifacts-builder`](https://docs) skill scaffolds — not a standalone app.
Build with the script at the repo root:

```bash
./build-explorer.sh
```

That extracts current agent frontmatter, scaffolds a fresh React/Vite project,
copies these files over it, and bundles everything into a single
self-contained `agent-explorer.html`.

| File | Role |
|------|------|
| `extract-agents.py` | Parses every agent's frontmatter → `agents-data.json` (stdout) |
| `agents-data.ts` | Imports the generated JSON and exports the typed `AGENTS` array |
| `App.tsx` | The explorer UI (search, category/schema filters, detail drawer) |
| `index.css` | Tailwind base + theme + technical-console styling |
| `index.html` | Entry HTML (title, root, module script) |

`agent-explorer.html` is a **snapshot** — re-run `build-explorer.sh` after
changing agents to refresh it.
