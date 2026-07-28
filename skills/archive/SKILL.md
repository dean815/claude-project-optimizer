---
name: archive
description: This skill should be used when the user asks to "archive this project", "retire this project", "I'm done with this project", "clean up this directory", "shut down this repo", "wind down this project", or asks how to safely stop working on a project. Inventories every store holding state for it — working directory, conversation history, worktrees, GitHub, Linear, and the optimizer registry — reports what would be lost, and archives it in a safe order. The counterpart to the onboard skill.
argument-hint: "[path] [--tier delete|cold|full|dormant] [--dry-run]"
allowed-tools: Read, Write, Bash, Glob, Grep, AskUserQuestion, Skill
---

# Archive a Project

Retire a project without orphaning the state that lives outside its directory.

**The governing rule: nothing is removed until its content is confirmed safe
somewhere else.** Verification comes before deletion, always, and deletion of the
originals comes last.

## Invocation

Default the path to the current working directory, and resolve it to an absolute
path — the registries are keyed by absolute path.

`--dry-run` produces the full plan and stops. `--tier` skips the tier question.

## Workflow

### 1. Preflight

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/archive-preflight.sh" "<absolute-path>"
```

This inventories all six stores and returns a `blockers` array — everything that
archiving would destroy. Read the whole object; the blockers list is a summary,
not the full picture.

Also run the ordinary scan, which supplies the archetype used to suggest a tier:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/scan-project.sh" "<absolute-path>" --no-github
```

If either emits an `error` key, stop and report it.

### 2. Propose a tier

Consult `${CLAUDE_PLUGIN_ROOT}/references/archive-tiers.md`. Map from the scan's
archetype, then confirm:

| Archetype | Suggested tier |
|---|---|
| `empty` | `delete` |
| `context-workspace` | `cold` |
| `library`, published tool, public repo with stars or forks | `dormant` |
| everything else | `full` |

State the suggestion and what it implies, then let the user correct it. The tier
determines how much of the rest of this workflow runs, so it is worth one
question rather than an assumption.

### 3. Report blockers before proposing anything

Blockers are work that exists in exactly one place. Present them plainly, with
the remedy for each, **before** the archive plan — the user may decide not to
archive at all once they see what is unsaved.

| Blocker | Remedy |
|---|---|
| Uncommitted changes | Commit, stash, or discard — the user's call |
| Unpushed commits | `git push` |
| No remote, commits exist only locally | Create a remote and push, or accept the loss explicitly |
| Stashes | Apply or drop; stashes are invisible after the directory moves |
| Branches not on the remote | Push or confirm they are abandoned |
| Worktrees with unsaved work | Resolve in the worktree before removing it |
| Untracked credential files | Decide per file — never copy one into a git repo |

**Do not resolve blockers automatically.** Committing or pushing on the user's
behalf makes decisions that are theirs. Present them, get direction, then act.

For `delete` and `cold` tiers most blockers do not apply; skip the ones that are
vacuous rather than listing them as satisfied.

### 4. Present the plan

Group by store, marked with what each action costs:

- **Move** — reversible
- **Remote** — affects GitHub or Linear
- **Remove** — irreversible; state exactly what is being removed and what holds
  the surviving copy

Include the conversation history size. Users routinely do not know it exists, and
it is often the largest single artifact — state the figure rather than a vague
reference to transcripts.

Then ask for approval in plain text. Accept partial approval.

### 5. Apply in order

Ordering is a safety property, not a preference. See the reference for why:

1. Push everything approved for pushing — the irreversible boundary
2. **Copy** history to the archive root (copy, not move)
3. Remove worktrees with `git worktree remove`, then `git worktree prune`
4. Move the working directory
5. `gh repo archive` if in scope
6. Update Linear
7. Deregister

Report each step as it completes. On failure, stop that store and continue with
the others, then say clearly what did not happen.

### 6. Verify before removing originals

After moving, confirm the archive actually contains what it should:

- The archived working directory exists and is non-empty
- The history directories are present, with file counts matching preflight
- For `full` and `dormant`: `git log origin/main..main` is empty

Only then remove the originals. When any check fails, leave everything in place
and report — a duplicated project is a minor annoyance, a lost one is not.

### 7. Deregister

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/registry.sh" set "<original-path>" declined
```

Recording the *original* path stops the hook from offering onboarding if the
directory is ever recreated. When the archive root sits outside `~/claude`, no
entry is needed for it.

Remove the `linear-sync` entry only if the project is going away entirely.

Close with what moved where, what was removed, and anything left undone.

## Safety constraints

- Never `git commit`, `git push`, `git stash drop`, or discard changes without
  explicit per-item approval
- Never delete a GitHub repository. `gh repo archive` is the only supported
  disposition; `--delete-repo` is permanent and breaks existing clones
- Never delete a Linear project — set its state instead, preserving issue history
- Never `rm -rf` a worktree; it corrupts the parent repo's metadata
- Never copy a credential file into a git repository
- Never make a public repository private as part of archiving
- Never remove conversation history before confirming the copy succeeded
- When the user is unsure about any store, leave it and say so. An
  incompletely archived project is recoverable; a deleted one is not

## Additional Resources

- **`${CLAUDE_PLUGIN_ROOT}/references/archive-tiers.md`** — The four tiers, the
  disposition of each store, and store-specific procedure
- **`${CLAUDE_PLUGIN_ROOT}/references/archetypes.md`** — Classification, which
  supplies the suggested tier
- **`${CLAUDE_PLUGIN_ROOT}/scripts/archive-preflight.sh`** — Inventory and blockers
- **`${CLAUDE_PLUGIN_ROOT}/scripts/scan-project.sh`** — Archetype classification
- **`${CLAUDE_PLUGIN_ROOT}/scripts/registry.sh`** — Deregistration
