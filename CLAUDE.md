# project-optimizer

A Claude Code plugin that onboards new project directories. The SessionStart
hook offers onboarding once per directory; the skills do the work.

## Commands

| Task | Command |
|---|---|
| Load for testing | `claude --plugin-dir .` |
| Scan a project | `bash scripts/scan-project.sh <path> [--no-github]` |
| Inspect state | `bash scripts/registry.sh list` |
| Reset a directory | `bash scripts/registry.sh remove <abs-path>` |
| Run tests | `bash tests/run.sh` |

## Architecture

Three layers, deliberately separated:

- `scripts/session-start.sh` — the hook. **Read-only by contract.** Decides
  whether to offer, never what to change.
- `scripts/scan-project.sh` — all deterministic detection, emitted as JSON.
  Facts live here so skills spend questions only on what a script cannot know.
- `skills/*/SKILL.md` — judgment. Reasons over scan JSON, proposes, applies.

State lives outside the repo at `~/.claude/project-optimizer/registry.json`,
keyed by absolute path. `session-start.sh` and `registry.sh` must canonicalize
paths identically (`cd … && pwd`) or entries silently never match.

`references/` is shared by the `onboard` and `audit` skills. Moving a file there
breaks both — update the `${CLAUDE_PLUGIN_ROOT}/references/…` pointers in each.

## Gotchas

- **Hook and plugin changes require a full Claude Code restart.** Editing
  `hooks/hooks.json` or the hook script has no effect on the running session.
- SessionStart also fires on `compact` and `clear`. The hook filters on
  `.source`; without that filter the offer re-injects mid-task.
- macOS ships neither `timeout` nor `gtimeout` — `run_bounded` falls back to a
  watchdog. Do not assume `timeout` exists.
- BSD `xargs -I` truncates its constructed argument at 255 bytes, silently
  breaking probes on long paths. Prefer a `while read` loop.
- Plugin `hooks.json` uses the wrapped form (`{"description", "hooks": {…}}`),
  not the flat settings form. The plugin-dev schema validator only understands
  the flat form and will report a false failure.

## Do not

- **Never interpolate a filename into a command string.** Filenames from
  `git ls-files` are untrusted — a repo can contain `a"; rm -rf ~; echo ".txt`.
  Read them as data (`while IFS= read -r -d ''`) and quote every use. This was a
  real vulnerability in `scan-project.sh`; `tests/run.sh` guards it.
- Never let the hook write anything. Its read-only contract is what makes firing
  broadly acceptable.
- Never put `die`/`exit` in a function called from a command substitution — it
  kills only the subshell and the caller continues with an empty value.
