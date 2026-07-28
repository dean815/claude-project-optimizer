# Project Archetypes

Reusable profiles that collapse most of the onboarding interview into a single
confirmation. Match the scan output against the signals below, state the inferred
archetype, and let the user correct it.

Archetypes are a starting point, not a straitjacket. When a project sits between
two, say so and take the stricter GitHub posture of the pair.

## Signal table

| Archetype | Primary signals from scan |
|---|---|
| `claude-plugin` | `.claude-plugin/plugin.json`, `skills/`, `agents/`, `hooks/hooks.json` |
| `mcp-server` | `mcp-sdk` in frameworks, `@modelcontextprotocol` dep, `fastmcp`, server entrypoint |
| `web-app` | `next`, `react`, `vue`, `svelte`, `astro`, `remix`, `nuxt`, `vite` in frameworks |
| `cli-tool` | `bin` field in package.json, `[project.scripts]` in pyproject, single entrypoint |
| `library` | Package manifest with no `bin`, published name, `exports`/`__init__.py` |
| `data-analysis` | `notebooks` in stack, `pandas`/`polars`/`jupyter`, `data/` directory |
| `automation` | Loose scripts, no manifest or minimal one, cron/n8n/webhook references |
| `experiment` | Few commits, no README, no remote, scratch-shaped names |

## Profiles

### claude-plugin

Building Claude Code plugins, skills, agents, or marketplaces.

- **Plugins**: `plugin-dev`, `skill-creator`, `hookify`, `commit-commands`
- **MCP**: none needed; plugin development is filesystem work
- **CLAUDE.md emphasis**: component inventory, the testing loop
  (`claude --plugin-dir .`), and the reload-requires-restart constraint that
  otherwise wastes debugging time
- **Layout**: `.claude-plugin/plugin.json`, `skills/<name>/SKILL.md`, `agents/`,
  `hooks/`, `scripts/`, `README.md`
- **GitHub rigor**: medium. Public if shared — then license and topics matter for
  marketplace discovery

### mcp-server

Model Context Protocol servers exposing tools to Claude and other clients.

- **Plugins**: `mcp-server-dev`, language LSP, `commit-commands`, `code-review`
- **MCP**: the server under development, pointed at the local build
- **CLAUDE.md emphasis**: tool inventory with signatures, transport (stdio vs SSE),
  required env vars **named but never valued**, and the local run command
- **Layout**: `src/`, `tests/`, `.env.example` (committed), `README.md` with client
  configuration examples
- **GitHub rigor**: high when public. Secret scanning matters more here than
  almost anywhere — MCP servers accumulate API credentials

### web-app

Front-end or full-stack web applications.

- **Plugins**: `frontend-design`, `playwright`, language LSP; `figma` only when
  designs actually live in Figma; `chrome-devtools-mcp` for debugging sessions
- **MCP**: `supabase` / `vercel` only when the project actually uses them
- **CLAUDE.md emphasis**: dev server command, routing convention, component
  location, styling system, and where **not** to put new components
- **Layout**: `src/` or `app/`, `public/`, `components/`, `tests/` or `e2e/`
- **GitHub rigor**: high when deployed. CI and branch protection earn their keep
  once a broken main means a broken site

### cli-tool

Command-line tools, personal or published.

- **Plugins**: language LSP, `commit-commands`, `code-review`
- **MCP**: none typically
- **CLAUDE.md emphasis**: the command surface, argument conventions, and how to
  run the tool locally without installing it
- **Layout**: `src/` or `bin/`, `tests/`, `README.md` with usage examples
- **GitHub rigor**: medium; high once published to a package registry

### library

Reusable packages intended for other code to import.

- **Plugins**: language LSP, `code-review`, `commit-commands`
- **MCP**: none
- **CLAUDE.md emphasis**: the public API surface and what is deliberately private,
  backward-compatibility expectations, and the release process
- **Layout**: `src/`, `tests/`, `docs/`, `CHANGELOG.md`
- **GitHub rigor**: highest. Consumers depend on the repo's contract — license,
  semver discipline, CI on every PR, and branch protection all matter

### data-analysis

Notebooks, pipelines, and exploratory analysis.

- **Plugins**: `pyright-lsp`, `data` plugins where connected
- **MCP**: warehouse or database connectors the project genuinely queries
- **CLAUDE.md emphasis**: data sources and their location, which notebooks are
  canonical versus exploratory, and any rule against committing data
- **Layout**: `notebooks/`, `data/` (usually gitignored), `src/`, `outputs/`
- **GitHub rigor**: low to medium, but `.gitignore` discipline is critical —
  datasets and credentials leak from this archetype more than any other

### automation

Personal glue: scripts, scheduled jobs, webhook handlers, home automation.

- **Plugins**: minimal. Language LSP and `commit-commands`
- **MCP**: whichever service the automation targets
- **CLAUDE.md emphasis**: what triggers it, what breaks if it stops, and where
  credentials live — usually the single most valuable thing to write down, because
  this archetype is the one most often revisited after months away
- **Layout**: flat is fine; a `scripts/` directory once past a handful of files
- **GitHub rigor**: low, but private-by-default unless deliberately public

### experiment

Throwaway or exploratory work.

- **Plugins**: leave global defaults; not worth scoping
- **MCP**: leave alone
- **CLAUDE.md emphasis**: one paragraph on what is being tried and why. Nothing more
- **Layout**: no expectations
- **GitHub rigor**: none. Do not propose creating a remote

For this archetype, propose the smallest possible change set — often just a short
CLAUDE.md — and consider suggesting `skip` with a snooze instead. Onboarding a
scratch directory is overhead that produces nothing.

## Choosing GitHub rigor

Rigor follows audience, not archetype alone. Confirm with the user rather than
assuming from file layout:

| Audience | Rigor | Means |
|---|---|---|
| Just the user, private | Low | `.gitignore`, README, no committed secrets |
| Shared with a few people | Medium | Above, plus license, description, CI |
| Public or depended upon | High | Above, plus branch protection, PR template, CODEOWNERS, Dependabot, secret scanning |
