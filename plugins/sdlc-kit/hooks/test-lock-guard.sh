#!/usr/bin/env bash
# PreToolUse guardrail for the sdlc-kit build loop:
#   - Edit/Write/MultiEdit on an add-only locked Python test file are allowed only if every locked
#     test, fixture and import is left intact (checked by lib/test_lock_ast.py). Adding tests is fine.
#   - Edits to whole-locked files (test support, non-Python tests) are blocked.
#   - Bash commands that write to a locked file, tamper with the lock file, or unlock are blocked.
#     Only humans unlock, from their own terminal.
# The Bash checks are a first line of defense only. `test-lock check`, run by the verifier, is the
# backstop: it proves with git that nothing locked has changed.
# Exit code 2 blocks the tool call and shows stderr to Claude.
set -euo pipefail

input=$(cat)
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
kit=$(cd "$here/.." && pwd)
root=${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}
lock="$root/.claude/test-lock"
tool=$(jq -r '.tool_name // empty' <<<"$input")

block() {
  echo "Blocked by test lock: $1" >&2
  echo "Make the code pass the locked tests unchanged. If a locked test itself is wrong, stop and tell the user why. Only they can unlock it, in their own terminal from the project root: \"$kit/bin/test-lock\" unlock <file>. A behavior change needs a spec amendment." >&2
  exit 2
}

# Mode of a locked path: the lock file's third column, or derived from the name (older lock files).
mode_of() {
  local lines=$1 rel=$2 m
  m=$(head -1 <<<"$lines" | cut -f3)
  if [[ -z "$m" ]]; then
    case "$(basename "$rel")" in test_*.py | *_test.py) m=add-only ;; *) m=whole ;; esac
  fi
  if [[ "$m" == add-only ]] && ! command -v python3 >/dev/null 2>&1; then m=whole; fi
  echo "$m"
}

if [[ "$tool" == "Bash" ]]; then
  cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
  if grep -Eq 'test-lock(\.sh)?["'"'"']?[[:space:]]+unlock' <<<"$cmd"; then
    block "agents can't unlock tests."
  fi
  # The lock file's path (`.claude/test-lock`), but not the words "test-lock" in prose such as
  # commit messages. Removing the lock by a bare name after `cd .claude` isn't caught here; the
  # verifier reports a missing lock on a branch with test commits.
  if grep -Eq '\.claude/test-lock($|[^A-Za-z0-9_.-])' <<<"$cmd"; then
    block "the lock file can only be changed through test-lock."
  fi
  [[ -s "$lock" ]] || exit 0
  # Block only when a locked file is the TARGET of a write: a redirect pointing at it, or a write
  # command with it as an argument in the same command segment. Naming the file is fine: commit
  # messages, `cat`, test runs, and redirects to other files all pass.
  verbs='sed[[:space:]]+-i|perl[[:space:]]+-i[^[:space:]]*|\btee\b|\bmv\b|\bcp\b|\brm\b|\btruncate\b|\bdd\b|\bpatch\b|git[[:space:]]+(checkout|restore|reset|stash|apply|am|cherry-pick|revert|rm|mv)\b'
  while IFS= read -r rel; do
    base=$(basename "$rel")
    esc=${base//./\\.}
    redirect=">{1,2}[[:space:]]*[\"']?[^[:space:]\"';|&]*${esc}"
    targeted="(${verbs})[^|;&]*${esc}"
    if grep -Eq "$redirect|$targeted" <<<"$cmd"; then
      block "this command looks like it writes to the locked file $rel. To add tests to an add-only locked test file, use the Edit tool."
    fi
  done < <(cut -f1 "$lock" | awk '!seen[$0]++')
  exit 0
fi

path=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input")
[[ -z "$path" ]] && exit 0
rel=${path#"$root"/}
rel=${rel#./}

if [[ "$rel" == ".claude/test-lock" ]]; then
  block "the lock file can only be changed through test-lock."
fi

[[ -s "$lock" ]] || exit 0
lines=$(awk -F'\t' -v r="$rel" '$1 == r' "$lock")
[[ -z "$lines" ]] && exit 0

if [[ "$(mode_of "$lines" "$rel")" == add-only ]]; then
  commits=$(cut -f2 <<<"$lines" | tr '\n' ' ')
  # shellcheck disable=SC2086
  if problems=$(printf '%s' "$input" | python3 "$kit/lib/test_lock_ast.py" guard "$root" "$rel" $commits); then
    exit 0
  fi
  block "$rel is locked add-only: you can add new tests, but this edit breaks the lock: $(tr '\n' ';' <<<"$problems" | sed 's/;$//; s/;/; /g')"
fi

first=$(head -1 <<<"$lines" | cut -f2)
block "$rel is locked (whole file, locked at ${first:0:8})."
