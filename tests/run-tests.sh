#!/usr/bin/env bash
# Regression suite for sdlc-kit's test lock and guard hooks. It runs the plugin's real bin/, lib/ and
# hooks/ files (not copies) against a throwaway git repo that plays the role of a project.
set -uo pipefail

KIT=$(cd "$(dirname "$0")/../plugins/sdlc-kit" && pwd)
L="$KIT/bin/test-lock"
G="$KIT/hooks/test-lock-guard.sh"
P="$KIT/hooks/guard-paths.sh"
SP=$(mktemp -d "${TMPDIR:-/tmp}/sdlc-kit-tests.XXXXXX")
trap 'rm -rf "$SP"' EXIT
mkdir -p "$SP/proj/tests/support" "$SP/web" "$SP/vendor/lib" "$SP/.claude"
cd "$SP" || exit 1
git init -q && git config user.email t@t && git config user.name t
export CLAUDE_PROJECT_DIR="$SP"
T=proj/tests/test_a.py
pass=0; fail=0

expect() {
  if [[ "$1" == "$3" ]]; then pass=$((pass+1)); printf 'ok    %-64s exit=%s\n' "$2" "$3"
  else fail=$((fail+1)); printf 'FAIL  %-64s exit=%s (expected %s)\n' "$2" "$3" "$1"; fi
}
run() { local want=$1 label=$2; shift 2; "$@" >/dev/null 2>&1; expect "$want" "$label" "$?"; }
hook() { printf '%s' "$4" | "$3" >/dev/null 2>&1; expect "$1" "$2" "$?"; }
bashcmd() { hook "$1" "$2" "$G" "$(jq -cn --arg c "$3" '{tool_name:"Bash",tool_input:{command:$c}}')"; }
edit() { hook "$1" "$2" "$G" "$(jq -cn --arg p "$SP/$3" --arg o "$4" --arg n "$5" '{tool_name:"Edit",tool_input:{file_path:$p,old_string:$o,new_string:$n}}')"; }
write() { hook "$1" "$2" "$G" "$(jq -cn --arg p "$SP/$3" --arg c "$4" '{tool_name:"Write",tool_input:{file_path:$p,content:$c}}')"; }
multiedit() { hook "$1" "$2" "$G" "$(jq -cn --arg p "$SP/$3" --argjson e "$4" '{tool_name:"MultiEdit",tool_input:{file_path:$p,edits:$e}}')"; }
paths() { hook "$1" "$2" "$P" "$(jq -cn --arg t "$3" --arg p "$SP/$4" '{tool_name:$t,tool_input:{file_path:$p}}')"; }

BASE='import pytest


def test_a():
    assert 1 == 1
'
NEW_TEST='

def test_b():
    assert 2 == 2
'

echo "== guard-paths: env files and protected paths"
paths 2 "Read .env" Read ".env"
paths 2 "Read nested .env.local" Read "proj/.env.local"
paths 0 "Read .env.example" Read ".env.example"
paths 0 "Edit a file with no protected-paths list" Edit "vendor/lib/x.py"
printf 'vendor/*   # vendored upstream\nsrc/gen/*.py\n\n# comment line\n' > .claude/protected-paths
paths 2 "Edit a protected path (vendor/*, nested)" Edit "vendor/lib/x.py"
paths 0 "Read a protected path" Read "vendor/lib/x.py"
paths 2 "Write a protected path (src/gen/*.py)" Write "src/gen/models.py"
paths 0 "Edit an unprotected path" Edit "proj/app.py"

echo "== test-lock: modes and lock points"
printf '%s' "$BASE" > $T
run 1 "lock with no commits yet -> refuse" "$L" lock $T
git add -A && git commit -qm init
echo "def test_x(): pass" > proj/tests/test_new.py
run 1 "lock uncommitted file -> refuse" "$L" lock proj/tests/test_new.py
rm proj/tests/test_new.py
echo "# local" >> $T
run 1 "lock file with local edits -> refuse" "$L" lock $T
git checkout -q -- $T
run 0 "lock python test file" "$L" lock $T
[[ "$("$L" status)" == *"(add-only)"* ]]; expect 0 "python test file is add-only" "$?"
run 0 "lock again unchanged" "$L" lock $T
[[ "$(grep -c . .claude/test-lock)" == 1 ]]; expect 0 "unchanged re-lock adds no lock point" "$?"
run 0 "check intact" "$L" check
( cd proj/tests && "$L" status >/dev/null 2>&1 ); expect 0 "works from a subdirectory" "$?"

echo "== check: add-only semantics"
printf '%s%s' "$BASE" "$NEW_TEST" > $T
run 0 "appending a new test keeps check green" "$L" check
printf '%s' "${BASE/1 == 1/1 == 2}" > $T
run 1 "changing a locked assertion fails check" "$L" check
printf 'import pytest, json\n\n\ndef test_a():\n    assert 1 == 1\n' > $T
run 0 "extending an import line is allowed" "$L" check
printf 'import json\n\n\ndef test_a():\n    assert 1 == 1\n' > $T
run 1 "removing an imported name fails check" "$L" check
printf '%s\n# a comment\n\n' "$BASE" > $T
run 0 "comments and blank lines are not changes" "$L" check
git checkout -q -- $T

echo "== lock points across steps"
printf '%s%s' "$BASE" "$NEW_TEST" > $T && git commit -qam "step 2 tests"
run 0 "lock after appending step 2 tests" "$L" lock $T
[[ "$(grep -c . .claude/test-lock)" == 2 ]]; expect 0 "second lock point recorded" "$?"
printf '%s%s' "$BASE" "${NEW_TEST/2 == 2/2 == 3}" > $T
run 1 "changing a step-2 test fails check" "$L" check
git commit -qam "sneaky"
run 1 "lock refuses when an earlier lock point is broken" "$L" lock $T
git revert --no-edit HEAD >/dev/null
run 0 "check intact after revert" "$L" check

echo "== test-lock guard: add-only file"
edit 0 "Edit appending a new test" $T "    assert 2 == 2" "    assert 2 == 2


def test_c():
    assert 3 == 3"
edit 2 "Edit changing a locked assertion" $T "assert 1 == 1" "assert True"
edit 2 "Edit adding a skip decorator to a locked test" $T "def test_a():" "@pytest.mark.skip
def test_a():"
edit 2 "Edit adding module-level pytestmark" $T "import pytest" "import pytest

pytestmark = pytest.mark.skip"
edit 2 "Edit adding a module-level pytest.skip call" $T "import pytest" "import pytest

pytest.skip('later', allow_module_level=True)"
edit 2 "Edit adding an autouse fixture" $T "import pytest" "import pytest


@pytest.fixture(autouse=True)
def _patch():
    yield"
edit 0 "Edit adding a normal fixture" $T "import pytest" "import pytest


@pytest.fixture
def value():
    return 1"
edit 2 "Edit leaving a file that doesn't parse" $T "def test_a():" "def test_a(:"
edit 0 "Edit adding a comment" $T "import pytest" "import pytest  # used by all tests"
write 0 "Write keeping every locked test plus a new one" $T "$BASE$NEW_TEST
def test_d():
    assert 4 == 4
"
write 2 "Write dropping a locked test" $T "$BASE"
multiedit 2 "MultiEdit with an append and a locked change" $T '[{"old_string":"    assert 2 == 2","new_string":"    assert 2 == 2\n\n\ndef test_e():\n    assert 5 == 5"},{"old_string":"assert 1 == 1","new_string":"assert 1 == 1 or True"}]'
multiedit 0 "MultiEdit with only appends" $T '[{"old_string":"    assert 2 == 2","new_string":"    assert 2 == 2\n\n\ndef test_e():\n    assert 5 == 5"}]'
hook 2 "NotebookEdit on an add-only file" "$G" "$(jq -cn --arg p "$SP/$T" '{tool_name:"NotebookEdit",tool_input:{notebook_path:$p}}')"

echo "== test-lock guard: whole-locked files"
echo "def app(): pass" > proj/tests/support/harness.py
echo "test('x', () => {})" > web/guest.test.ts
git add -A && git commit -qm "support + ts"
run 0 "lock support file and ts test" "$L" lock proj/tests/support/harness.py web/guest.test.ts
s=$("$L" status)
[[ "$s" == *"(whole): proj/tests/support/harness.py"* && "$s" == *"(whole): web/guest.test.ts"* ]]; expect 0 "support and non-python tests are whole-locked" "$?"
edit 2 "Edit appending to whole-locked support file" proj/tests/support/harness.py "def app(): pass" "def app(): pass
def extra(): pass"
edit 2 "Edit appending to whole-locked ts test" web/guest.test.ts "test('x', () => {})" "test('x', () => {})
test('y', () => {})"
echo "def app(): return 1" > proj/tests/support/harness.py && git commit -qam "edit support"
run 1 "check fails on changed whole-locked file" "$L" check
git revert --no-edit HEAD >/dev/null
edit 0 "Edit to an unlocked file" proj/app.py "a" "b"

echo "== test-lock guard: Bash (write targets only)"
bashcmd 0 "commit message naming a locked test, with <slug>" "git commit -m 'test(<slug>): step 2: cover tests/test_a.py'"
bashcmd 0 "test run redirected to another file" "uv run pytest $T > /tmp/out.txt 2>&1"
bashcmd 0 "cat locked test" "cat $T"
bashcmd 2 "append redirect into locked test" "echo x >> $T"
bashcmd 2 "sed -i on locked test" "sed -i '' s/1/2/ $T"
bashcmd 2 "mv locked test away" "mv $T /tmp/x.py"
bashcmd 2 "git checkout of locked test" "git checkout HEAD~1 -- $T"
bashcmd 2 "agent unlock by name" "test-lock unlock $T"
bashcmd 2 "agent unlock by quoted plugin path" "\"$KIT/bin/test-lock\" unlock"
bashcmd 2 "agent unlock via legacy .sh name" ".claude/hooks/test-lock.sh unlock"
bashcmd 2 "rm the lock file by path" "rm .claude/test-lock"
bashcmd 0 "status via test-lock" "test-lock status"
bashcmd 0 "prose mentioning test-lock and unlocking" "git commit -m 'explain how humans unlock tests'"
out=$(jq -cn --arg p "$SP/$T" '{tool_name:"Edit",tool_input:{file_path:$p,old_string:"assert 1 == 1",new_string:"assert True"}}' | "$G" 2>&1)
[[ "$out" == *"$KIT/bin/test-lock\" unlock"* ]]; expect 0 "block message prints the exact unlock path" "$?"

echo "== human unlock"
run 0 "unlock only the support file" "$L" unlock proj/tests/support/harness.py
s=$("$L" status)
[[ "$s" != *"harness.py"* && "$s" == *"test_a.py"* ]]; expect 0 "others stay locked" "$?"
run 0 "unlock the add-only file removes all its lock points" "$L" unlock $T
[[ "$(grep -c 'test_a.py' .claude/test-lock)" == 0 ]]; expect 0 "no lock points left for it" "$?"
printf '%s\t%s\n' "$T" "$(git rev-parse HEAD)" > .claude/test-lock
[[ "$("$L" status)" == *"(add-only): $T"* ]]; expect 0 "two-column lock line derives add-only" "$?"
printf '%s\t%s\tadd-only\n' "$T" "0123456789abcdef0123456789abcdef01234567" > .claude/test-lock
out=$("$L" check 2>&1); code=$?
[[ $code == 1 && "$out" == *"can't be read from git"* && "$out" != *Traceback* ]]; expect 0 "unreadable lock point fails check cleanly" "$?"
run 0 "unlock all" "$L" unlock
edit 0 "Edit test with no lock" $T "assert 1 == 1" "assert True"

echo "== $pass passed, $fail failed"
[[ $fail -eq 0 ]]
