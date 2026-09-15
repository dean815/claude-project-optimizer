#!/bin/bash
# project-optimizer — SessionStart hook (STRICTLY READ-ONLY).
#
# Fires on every session start. If the current directory has never been
# onboarded, declined, or snoozed, it emits a SessionStart additionalContext
# message asking the assistant to OFFER onboarding — it does not start it.
#
# This script NEVER creates, modifies, or deletes anything. The registry is
# written only by the /project-optimizer:onboard and :skip skills.
#
# Registry: ~/.claude/project-optimizer/registry.json  (keyed by absolute path)

set -uo pipefail

# Kept in sync with registry.sh — see the note there on PROJECT_OPTIMIZER_HOME.
REGISTRY="${PROJECT_OPTIMIZER_HOME:-${HOME}/.claude/project-optimizer}/registry.json"

# --- Resolve the project directory ----------------------------------------
# SessionStart hooks receive JSON on stdin containing "cwd".
STDIN_JSON="$(cat 2>/dev/null || true)"
PROJECT_DIR=""
SOURCE=""
if [ -n "$STDIN_JSON" ] && command -v jq >/dev/null 2>&1; then
  PROJECT_DIR="$(printf '%s' "$STDIN_JSON" | jq -r '.cwd // empty' 2>/dev/null || true)"
  SOURCE="$(printf '%s' "$STDIN_JSON" | jq -r '.source // empty' 2>/dev/null || true)"
fi
[ -z "$PROJECT_DIR" ] && PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"

# SessionStart also fires on compaction and /clear. Re-injecting the offer then
# would interrupt work in progress — exactly what this hook promises not to do.
case "$SOURCE" in
  compact|clear) exit 0 ;;
esac

PROJECT_DIR="${PROJECT_DIR%/}"
[ -z "$PROJECT_DIR" ] && exit 0
[ -d "$PROJECT_DIR" ] || exit 0

# Canonicalize exactly as registry.sh does, so the key this hook looks up is
# always the key the skills write. Without this, a symlinked path (macOS /tmp
# vs /private/tmp) records under one key and is looked up under another, and
# the offer returns forever in a directory that was already onboarded.
PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd)" || exit 0
[ -z "$PROJECT_DIR" ] && exit 0

# --- Ignore only genuine noise --------------------------------------------
# Deliberately narrow: the preference is to fire too often rather than too
# little. The offer is a single line and always asks before doing anything.
case "$PROJECT_DIR" in
  "$HOME"|"/"|"") exit 0 ;;
  "$HOME/.claude"|"$HOME/.claude/"*) exit 0 ;;
  "$HOME/Downloads"|"$HOME/Downloads/"*) exit 0 ;;
  "$HOME/Desktop"|"$HOME/.Trash"|"$HOME/.Trash/"*) exit 0 ;;
  /tmp|/private/tmp|/tmp/*|/private/tmp/*|/private/var/folders/*|/var/folders/*) exit 0 ;;
  *"/node_modules/"*|*"/.git/"*|*"/vendor/"*|*"/.venv/"*|*"/site-packages/"*) exit 0 ;;
esac

# --- Worktrees belong to their parent repo ---------------------------------
# A linked git worktree (git worktree add, or Claude Code's own
# .claude/worktrees/<name>) is a scratch copy of a project, not a project. Look
# the offer up under the main working tree, so onboarding the parent once
# silences every worktree of it — and so a session that opens in a worktree
# (about half of them, on a worktree-heavy setup) still gets the offer instead
# of being skipped as noise.
WORKTREE_OF=""
COMMON="$(git -C "$PROJECT_DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
if [ -z "$COMMON" ]; then
  # git < 2.31 has no --path-format; the plain form may come back relative.
  COMMON="$(git -C "$PROJECT_DIR" rev-parse --git-common-dir 2>/dev/null || true)"
  case "$COMMON" in
    ""|/*) ;;
    *) COMMON="$PROJECT_DIR/$COMMON" ;;
  esac
fi
GIT_DIR_HERE="$(git -C "$PROJECT_DIR" rev-parse --path-format=absolute --git-dir 2>/dev/null \
  || git -C "$PROJECT_DIR" rev-parse --git-dir 2>/dev/null || true)"
case "$GIT_DIR_HERE" in ""|/*) ;; *) GIT_DIR_HERE="$PROJECT_DIR/$GIT_DIR_HERE" ;; esac
if [ -n "$COMMON" ] && [ -n "$GIT_DIR_HERE" ] && [ "$COMMON" != "$GIT_DIR_HERE" ]; then
  # Linked worktree: the common dir is the parent's .git; its parent is the repo.
  MAIN="$(cd "$(dirname "$COMMON")" 2>/dev/null && pwd)"
  if [ -n "$MAIN" ] && [ "$MAIN" != "$PROJECT_DIR" ]; then
    WORKTREE_OF="$PROJECT_DIR"; PROJECT_DIR="$MAIN"
  fi
fi
# Not a git worktree but shaped like one (a worktree whose repo was deleted,
# or a copy): fall back to the path convention.
if [ -z "$WORKTREE_OF" ]; then
  case "$PROJECT_DIR" in
    *"/.claude/worktrees/"*)
      MAIN="${PROJECT_DIR%%/.claude/worktrees/*}"
      [ -d "$MAIN" ] && { WORKTREE_OF="$PROJECT_DIR"; PROJECT_DIR="$MAIN"; }
      ;;
  esac
fi

# --- Already known? Stay silent -------------------------------------------
NOW_EPOCH="$(date +%s 2>/dev/null || echo 0)"
if [ -f "$REGISTRY" ] && command -v jq >/dev/null 2>&1; then
  STATUS="$(jq -r --arg p "$PROJECT_DIR" \
    '.projects[$p].status // empty' "$REGISTRY" 2>/dev/null || true)"
  case "$STATUS" in
    optimized|declined) exit 0 ;;
    snoozed)
      UNTIL="$(jq -r --arg p "$PROJECT_DIR" \
        '.projects[$p].snoozeUntil // 0' "$REGISTRY" 2>/dev/null || echo 0)"
      # Still snoozed -> silent. Expired -> fall through and offer again.
      [ "$UNTIL" -gt "$NOW_EPOCH" ] 2>/dev/null && exit 0
      ;;
  esac
elif [ -f "$REGISTRY" ]; then
  # jq unavailable: best-effort substring match so we fail quiet, not noisy.
  grep -q "\"${PROJECT_DIR}\"" "$REGISTRY" 2>/dev/null && exit 0
fi

# --- Cheap peek so the offer is informative (a handful of stat calls) ------
NAME="$(basename "$PROJECT_DIR")"
FACTS=""

if [ -d "$PROJECT_DIR/.git" ] || git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  REMOTE="$(git -C "$PROJECT_DIR" remote get-url origin 2>/dev/null || true)"
  if [ -n "$REMOTE" ]; then
    FACTS="git repo with remote"
  else
    FACTS="git repo, no remote"
  fi
else
  FACTS="not a git repo"
fi

[ -f "$PROJECT_DIR/CLAUDE.md" ] && FACTS="$FACTS; has CLAUDE.md" || FACTS="$FACTS; no CLAUDE.md"
[ -f "$PROJECT_DIR/.claude/settings.json" ] \
  && FACTS="$FACTS; has project settings" \
  || FACTS="$FACTS; no project-scoped settings"
[ -f "$PROJECT_DIR/README.md" ] || FACTS="$FACTS; no README"

WT_NOTE=""
[ -n "$WORKTREE_OF" ] && WT_NOTE=" NOTE: this session runs in a worktree (${WORKTREE_OF}) of that project. The path above is the parent repository — pass THAT path to the skills, never the worktree path, so the record covers the project and all its worktrees."

MSG="Project optimizer: this is the first Claude Code session in \"${NAME}\" (${PROJECT_DIR}). Quick scan: ${FACTS}. ASK the user — in one short question, do not start yet — whether they want to run project onboarding now. Onboarding tunes which plugins and MCP servers load for this project, writes or improves CLAUDE.md, checks directory organization, and verifies GitHub configuration; it always presents a plan before changing anything. If yes, invoke the Skill tool with skill 'project-optimizer:onboard' and pass this exact path: ${PROJECT_DIR}. If they decline OR defer it in any way — 'no', 'never', 'not now', 'later', 'remind me next week' — you must invoke the Skill tool with 'project-optimizer:skip' and that same path. Saying you have snoozed or declined it without invoking that skill records nothing, and the offer returns on the very next session while the user believes it will not. TIMING: if their first message is a greeting or carries no task, ask right away. If it carries a task — the usual case — handle that request first, in full, and then raise this offer in one line at the end of that same reply. Do not skip it because the session opened with work: nothing is recorded when you stay silent, so the offer returns every session and the user never sees it. Never block or delay their actual request for this.${WT_NOTE}"

# --- Emit SessionStart additionalContext ----------------------------------
if command -v jq >/dev/null 2>&1; then
  jq -n --arg ctx "$MSG" \
    '{hookSpecificOutput:{hookEventName:"SessionStart", additionalContext:$ctx}}'
else
  ESCAPED="$(printf '%s' "$MSG" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$ESCAPED"
fi

exit 0
