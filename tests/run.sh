#!/bin/bash
# project-optimizer — regression tests.
#
# Each test guards a bug that actually shipped or nearly shipped. Run before
# committing changes to anything in scripts/.
#
#   bash tests/run.sh

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"

# mktemp returns /var/folders/… on macOS, which session-start.sh correctly
# suppresses as noise. Hook tests therefore need a fixture somewhere the hook
# would genuinely fire, or they pass for the wrong reason.
HOOK_TMP="$ROOT/.test-tmp"
rm -rf "$HOOK_TMP"
trap 'rm -rf "$TMP" "$HOOK_TMP"' EXIT

PASS=0; FAIL=0
ok()  { printf '  ok    %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }
assert() { if [ "$1" = "true" ]; then ok "$2"; else bad "$2"; fi; }

command -v jq >/dev/null 2>&1 || { echo "jq is required to run these tests"; exit 1; }

# A repo whose tracked filename is crafted to break out of a shell string,
# plus a file large enough for the oversized-file probe to find.
make_fixture() {
  local d="$1"
  mkdir -p "$d"
  (
    cd "$d" || exit 1
    git init -q .
    git config user.email test@example.com
    git config user.name test
    evil='a"; touch PWNED; echo ".txt'
    printf 'x' > "$evil"
    dd if=/dev/zero of=big.bin bs=1024 count=1200 2>/dev/null
    git add -A >/dev/null 2>&1
    git commit -qm fixture >/dev/null 2>&1
  )
}

echo "project-optimizer regression tests"
echo

# --------------------------------------------------------------------------
echo "[security]"
REPO="$TMP/evil"
make_fixture "$REPO"
rm -f "$TMP/PWNED" "$REPO/PWNED"
( cd "$TMP" && bash "$ROOT/scripts/scan-project.sh" "$REPO" --no-github >/dev/null 2>&1 )
if [ -f "$TMP/PWNED" ] || [ -f "$REPO/PWNED" ]; then
  bad "tracked filename cannot inject shell code"
else
  ok "tracked filename cannot inject shell code"
fi

# The injected fragment used to surface as a bogus extra array entry.
ENTRIES="$(bash "$ROOT/scripts/scan-project.sh" "$REPO" --no-github 2>/dev/null \
  | jq -r '.layout.largeTracked | length')"
assert "$([ "${ENTRIES:-0}" -eq 1 ] && echo true || echo false)" \
  "largeTracked reports exactly the one oversized file (got ${ENTRIES:-0})"

# --------------------------------------------------------------------------
echo
echo "[probes]"
# BSD xargs -I truncated at 255 bytes, silently emptying this probe on long paths.
DEEP="$TMP/a/very/deeply/nested/path/that/exceeds/the/bsd/xargs/limit/for/sure/ok"
mkdir -p "$DEEP" && cp -R "$REPO/." "$DEEP/" 2>/dev/null
FOUND="$(bash "$ROOT/scripts/scan-project.sh" "$DEEP" --no-github 2>/dev/null \
  | jq -r '.layout.largeTracked | length')"
assert "$([ "${FOUND:-0}" -ge 1 ] && echo true || echo false)" \
  "largeTracked still works from a long path"

# .env.example is good practice and must not be flagged as a leaked secret.
SAFE="$TMP/safe"
mkdir -p "$SAFE"
( cd "$SAFE" && git init -q . && git config user.email t@e.com && git config user.name t \
  && printf 'API_KEY=\n' > .env.example && git add -A >/dev/null 2>&1 \
  && git commit -qm x >/dev/null 2>&1 )
RISKY="$(bash "$ROOT/scripts/scan-project.sh" "$SAFE" --no-github 2>/dev/null \
  | jq -r '.layout.riskyTracked | length')"
assert "$([ "${RISKY:-1}" -eq 0 ] && echo true || echo false)" \
  ".env.example is not flagged as risky"

# Error paths must still emit parseable JSON — skills are told to read it.
bash "$ROOT/scripts/scan-project.sh" '/nonexistent/pa"th' --no-github 2>/dev/null \
  | jq empty >/dev/null 2>&1 \
  && ok "invalid path still emits valid JSON" \
  || bad "invalid path still emits valid JSON"

# --------------------------------------------------------------------------
echo
echo "[hook]"
# Fixture in a location the hook treats as a real project, not a noise dir.
HOOK_REPO="$HOOK_TMP/proj"
make_fixture "$HOOK_REPO"
bash "$ROOT/scripts/registry.sh" remove "$HOOK_REPO" >/dev/null 2>&1

# SessionStart fires on compaction and /clear too; re-offering then interrupts work.
for src in startup resume; do
  OUT="$(echo "{\"cwd\":\"$HOOK_REPO\",\"source\":\"$src\"}" | bash "$ROOT/scripts/session-start.sh")"
  assert "$([ -n "$OUT" ] && echo true || echo false)" "hook fires on '$src'"
done
for src in compact clear; do
  OUT="$(echo "{\"cwd\":\"$HOOK_REPO\",\"source\":\"$src\"}" | bash "$ROOT/scripts/session-start.sh")"
  assert "$([ -z "$OUT" ] && echo true || echo false)" "hook is silent on '$src'"
done

# Noise directories must never be offered.
for d in "$HOME" "$HOME/Downloads" /tmp /private/tmp "$HOME/.claude"; do
  OUT="$(echo "{\"cwd\":\"$d\",\"source\":\"startup\"}" | bash "$ROOT/scripts/session-start.sh")"
  assert "$([ -z "$OUT" ] && echo true || echo false)" "hook is silent in $d"
done

# The offer must not hardcode a personal name or gendered pronouns.
grep -qE '\bDean\b|\bhe\b|\bhis\b' "$ROOT/scripts/session-start.sh" \
  && bad "hook text is audience-neutral" \
  || ok "hook text is audience-neutral"

# --------------------------------------------------------------------------
echo
echo "[registry]"
# die inside a command substitution killed only the subshell; callers saw success.
bash "$ROOT/scripts/registry.sh" get >/dev/null 2>&1
assert "$([ $? -ne 0 ] && echo true || echo false)" "get without a path exits non-zero"
bash "$ROOT/scripts/registry.sh" remove >/dev/null 2>&1
assert "$([ $? -ne 0 ] && echo true || echo false)" "remove without a path exits non-zero"

# A relative key never matched the hook's absolute cwd, so skips silently failed.
( cd "$TMP" && bash "$ROOT/scripts/registry.sh" set "./evil" declined >/dev/null 2>&1 )
STORED="$(bash "$ROOT/scripts/registry.sh" list 2>/dev/null | grep -c "$TMP" || true)"
assert "$([ "${STORED:-0}" -ge 1 ] && echo true || echo false)" \
  "relative paths are stored as absolute"

# Recorded directories must actually silence the hook. Uses the non-noise
# fixture so a pass means the registry worked, not that the path was ignored.
bash "$ROOT/scripts/registry.sh" set "$HOOK_REPO" optimized claude-plugin >/dev/null 2>&1
OUT="$(echo "{\"cwd\":\"$HOOK_REPO\",\"source\":\"startup\"}" | bash "$ROOT/scripts/session-start.sh")"
assert "$([ -z "$OUT" ] && echo true || echo false)" \
  "a recorded directory silences the hook"
bash "$ROOT/scripts/registry.sh" remove "$HOOK_REPO" >/dev/null 2>&1

# --------------------------------------------------------------------------
echo
echo "[manifest]"
for f in .claude-plugin/plugin.json hooks/hooks.json; do
  jq empty "$ROOT/$f" >/dev/null 2>&1 && ok "$f is valid JSON" || bad "$f is valid JSON"
done
jq -e '.hooks.SessionStart' "$ROOT/hooks/hooks.json" >/dev/null 2>&1 \
  && ok "hooks.json uses the wrapped plugin format" \
  || bad "hooks.json uses the wrapped plugin format"
for f in "$ROOT"/scripts/*.sh "$ROOT"/tests/*.sh; do
  bash -n "$f" 2>/dev/null && ok "$(basename "$f") parses" || bad "$(basename "$f") parses"
done

# --------------------------------------------------------------------------
echo
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
