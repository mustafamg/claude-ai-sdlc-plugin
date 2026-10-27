#!/usr/bin/env bash
# Regression suite for sdlc-kit's test lock, guard hooks and intents tool. It runs the plugin's real
# bin/, lib/ and hooks/ files (not copies) against throwaway git repos that play the role of a project.
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
unset INTENTS_BASE  # a project's settings may set it; these repos rely on origin/HEAD
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

echo "== test-lock guard: Bash (data is not execution)"
bashcmd 0 "grep the lock file" "grep -c . .claude/test-lock"
bashcmd 0 "cat the lock file" "cat .claude/test-lock"
bashcmd 0 "grep the guard's own source" "grep -n 'claude/test-lock' $KIT/hooks/test-lock-guard.sh"
bashcmd 0 "commit message naming the lock path" "git commit -m 'docs: the state file is .claude/test-lock, never committed'"
bashcmd 0 "commit message quoting the unlock command" "git commit -m 'docs: humans run \"\$KIT/bin/test-lock\" unlock <file> themselves'"
bashcmd 0 "heredoc documenting the unlock command" "cat > docs/locks.md <<'EOF'
Only humans unlock: \"<plugin path>/bin/test-lock\" unlock <file>
The state lives in .claude/test-lock and is gitignored.
EOF"
bashcmd 0 "commit message from a heredoc naming the lock path" "git commit -q -F - <<'EOF'
chore: adopt the plugin

The lock keeps using .claude/test-lock, so existing locks stay visible.
EOF"
bashcmd 0 "python script that writes docs about unlocking" "python3 /tmp/write_docs.py  # writes 'test-lock unlock' into a README"
bashcmd 2 "unlock inside bash -c is still blocked" "bash -c '$KIT/bin/test-lock unlock $T'"
bashcmd 2 "redirect into the lock file is still blocked" "echo junk > .claude/test-lock"
bashcmd 2 "truncate of the lock file is still blocked" "truncate -s0 .claude/test-lock"
bashcmd 2 "git checkout of the lock file is still blocked" "git checkout HEAD -- .claude/test-lock"
bashcmd 2 "write to a locked test inside a heredoc-bearing command is still blocked" "sed -i '' s/1/2/ $T; cat <<'EOF'
done
EOF"
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

# ---------------------------------------------------------------- intents
# A second throwaway project with intents at every stage, a bare origin, and a draft that exists
# only on origin's docs/intent-* branch.
I="$KIT/bin/intents"
IH="$KIT/hooks/intents-check.sh"
IP="$SP/ip"
mkdir -p "$IP" && cd "$IP" || exit 1
git init -q -b main && git config user.email t@t && git config user.name t
at() { local d=$1; shift; GIT_AUTHOR_DATE="${d}T12:00:00" GIT_COMMITTER_DATE="${d}T12:00:00" "$@"; }
mkintent() { # folder status [header lines] [out-of-scope lines]
  mkdir -p "intent/$1"
  printf '# Intent: %s\n\n- **Author:** t\n- **Status:** %s\n%b\n## Problem\nx\n\n## Out of scope\n%b\n' \
    "$1" "$2" "${3:-}" "${4:-}" > "intent/$1/intent.md"
}
# subst <file> <from> <to>: replace once, and fail loudly if <from> isn't there.
subst() { python3 -c 'import sys; p, a, b = sys.argv[1:]; s = open(p).read(); assert a in s, a; open(p, "w").write(s.replace(a, b, 1))' "$@"; }
ireset() { git checkout -q -- . && git clean -fdq intent .claude; }
# outp <exit> <label> <regex> <cmd...>: the command exits <exit> and its output matches <regex>.
outp() {
  local want=$1 label=$2 pat=$3 o c; shift 3
  o=$("$@" 2>&1); c=$?
  grep -Eq -- "$pat" <<<"$o" || c="$c, no match for /$pat/"
  expect "$want" "$label" "$c"
}
# outn: as outp, but the output must not match.
outn() {
  local want=$1 label=$2 pat=$3 o c; shift 3
  o=$("$@" 2>&1); c=$?
  grep -Eq -- "$pat" <<<"$o" && c="$c, matched /$pat/"
  expect "$want" "$label" "$c"
}
ih() { printf '%s' "$1" | "$IH"; }  # feed hook JSON to the intents hook; with outn ... ., expect no output
iedit() { jq -cn --arg p "$IP/$1" --arg n "$2" '{tool_name:"Edit",tool_input:{file_path:$p,old_string:"x",new_string:$n}}'; }
iwrite() { jq -cn --arg p "$IP/$1" '{tool_name:"Write",tool_input:{file_path:$p,content:"x"}}'; }

mkintent 2026-01-01-alpha accepted "" "- **Old data.** → follow-up: omega"
mkintent 2026-01-02-beta accepted "- **Depends on:** #10\n"
mkintent 2026-01-03-gamma accepted "- **Depends on:** alpha\n"
cat >> intent/2026-01-03-gamma/intent.md <<'EOF'

## Stories
Each story ships on its own.

- **S1 g-one**: the backend. Outcomes: 1.
- **S2 g-two**: the admin page. Outcomes: 2. After: S1.
- **S3 g-three**: the chat UI. Outcomes: 3. After: S2 ships, chatui-accounts.
- ~~**S4 g-four**: exports. After: S1.~~ (Dropped 2026-01-04: not needed.)
EOF
mkintent 2026-01-04-delta deferred "- **Revisit:** 2026-06 (t)\n"
mkintent 2026-01-05-theta accepted
cat >> intent/2026-01-05-theta/intent.md <<'EOF'

## Stories
Each story ships on its own. `After: S1` waits for S1's spec.

### S1 <story-slug>: <title>
- **After:** <S1, S1 ships, or a slug; delete if none>

### S1 t-one: Build rules visually
Analysts build a rule in a visual builder.

- **Outcomes:** 1
- **Actors:** analysts

**What users get**
- A builder.
  - Nested under it.

**Acceptance criteria**
- An analyst can save a rule.

### S2 t-two: Chain conditions with AND, OR and NOT
- **Outcomes:** 2
- **After:** S1 ships

**Acceptance criteria**
- A rule with three conditions joined by AND fires only when all three hold.

### ~~S3 t-three: Export rules~~ (Dropped 2026-01-05: not needed.)
- **After:** S9
EOF
mkintent 2026-01-06-zeta accepted
mkdir -p .claude/skills/api-security .claude/skills/helper
printf -- '---\nname: api-security\ndescription: Policy - API rules.\n---\n\n- The dashboard calls Dify directly. → follow-up: dify-gateway\n' > .claude/skills/api-security/SKILL.md
printf -- '---\nname: helper\ndescription: Helps.\n---\n\nThis is a separate intent. → follow-up: helper-thing\n' > .claude/skills/helper/SKILL.md
git add -A && at 2026-01-04 git commit -qm "docs(intent): intents"
echo s > intent/2026-01-01-alpha/spec.md && echo p > intent/2026-01-01-alpha/plan.md
echo s > intent/2026-01-02-beta/spec.md
mkdir -p intent/2026-01-03-gamma/g-one && echo s > intent/2026-01-03-gamma/g-one/spec.md && echo p > intent/2026-01-03-gamma/g-one/plan.md
git switch -q -c docs/spec && git add -A && at 2026-01-05 git commit -qm "docs(spec): specs"
git switch -q main && at 2026-01-06 git merge -q --no-ff docs/spec -m "Merge spec PR"
git switch -q -c feat/alpha
echo t > t_alpha && git add -A && at 2026-01-08 git commit -qm "test(alpha): step 1: A1"
echo c > c_alpha && git add -A && at 2026-01-09 git commit -qm "feat(alpha): step 1: thing"
git switch -q main && at 2026-01-10 git merge -q --no-ff feat/alpha -m "Merge pull request #3 from x/feat/alpha"
echo z > z && git add -A && at 2026-01-11 git commit -qm "feat: zeta (#5)" -m "* test(zeta): step 1: A1
* feat(zeta): step 1: thing"
git switch -q -c feat/g-one && echo t > t_gone && git add -A && at 2026-01-12 git commit -qm "test(g-one): step 1: A1"
echo c > c_gone && git add -A && at 2026-01-12 git commit -qm "feat(g-one): step 1: backend"
git switch -q main && git switch -q -c docs/intent-epsilon && mkintent 2026-01-07-epsilon draft
git add -A && at 2026-01-13 git commit -qm "docs(intent): epsilon" && git switch -q main
git init -q --bare "$SP/ip-origin.git" && git remote add origin "$SP/ip-origin.git"
git push -q origin main feat/g-one docs/intent-epsilon 2>/dev/null && git remote set-head origin main >/dev/null
git branch -q -D docs/intent-epsilon feat/g-one feat/alpha docs/spec && git fetch -q origin
mkdir -p "$SP/gh-merged" "$SP/gh-open"
printf '#!/bin/sh\n[ "$1" = pr ] && echo MERGED\n' > "$SP/gh-merged/gh"
printf '#!/bin/sh\n[ "$1" = pr ] && echo OPEN\n' > "$SP/gh-open/gh"
chmod +x "$SP/gh-merged/gh" "$SP/gh-open/gh"

echo "== intents status: stages are derived from git"
outp 0 "a merged feature branch is shipped" '2026-01-01-alpha +shipped +since 2026-01-09' "$I" status
outp 0 "a squash merge body counts as shipped" '2026-01-06-zeta +shipped' "$I" status
outp 0 "specced is dated by the merge, not the branch commit" '2026-01-02-beta +specced +since 2026-01-06' "$I" status
outp 0 "step commits on an unmerged branch mean building" 'S1 g-one +building' "$I" status
outp 0 "a story with nothing merged is accepted" 'S2 g-two +accepted' "$I" status
outp 0 "a struck-through story is dropped" 'S4 g-four +dropped' "$I" status
outp 0 "a story under its own heading is read" 'S1 t-one +accepted' "$I" status
outp 0 "a struck-through story heading is dropped" 'S3 t-three +dropped' "$I" status
outp 0 "After under a story heading is read" 'S2 t-two .*waiting on S1 \(needs to ship, is accepted\)' "$I" status
outp 0 "an intent with stories rolls up" '2026-01-03-gamma +in progress +0 of 3 stories shipped' "$I" status
outp 0 "deferred shows its revisit month" '2026-01-04-delta +deferred .*revisit 2026-06' "$I" status
outp 0 "a draft only on origin's docs/intent-* branch is listed" '2026-01-07-epsilon +draft +on origin/docs/intent-epsilon' "$I" status
outp 0 "unmet dependencies are shown" 'S3 g-three .*waiting on S2 \(needs to ship, is accepted\), chatui-accounts \(needs to ship, is reserved\)' "$I" status
outp 0 "a follow-up marker reserves its slug" 'omega +promised at intent/2026-01-01-alpha/intent.md:10' "$I" status
outp 0 "a policy skill's marker reserves too" 'dify-gateway +promised at \.claude/skills/api-security/SKILL\.md' "$I" status
outp 0 "a dependency on nothing is reserved, with who waits" 'chatui-accounts +named at .*waited on by g-three' "$I" status
outn 0 "a non-policy skill's marker reserves nothing" 'helper-thing' "$I" status
outn 0 "status <slug> shows only that intent" '2026-01-01-alpha' "$I" status g-three
outp 2 "status of an unknown slug" 'no intent or story' "$I" status nope
mkintent 2026-01-08-eta accepted "- **Supersedes:** \`intent/2026-01-07-epsilon\` (never merged). Folded in below.\n"
git add -A && git commit -qm "docs(intent): eta"
outp 0 "a draft folded into a merged intent shows as superseded" '2026-01-07-epsilon +superseded +by eta, and its branch origin/docs/intent-epsilon still exists' "$I" status --base main
git branch -q develop "$(git log -1 --format=%H --grep='^docs(intent): intents$')"
outp 0 "INTENTS_BASE picks the default branch" 'Intents \(develop\)' env INTENTS_BASE=develop "$I" status
outp 0 "status is read from that branch" '2026-01-02-beta +accepted' env INTENTS_BASE=develop "$I" status
outp 0 "--base wins over INTENTS_BASE" 'Intents \(main\)' env INTENTS_BASE=develop "$I" status --base main
outp 2 "a default branch that doesn't exist is refused" "'origin/nope' isn't a commit here" env INTENTS_BASE=origin/nope "$I" status
git branch -q -D develop
git reset -q --hard origin/main

echo "== intents deps"
outp 0 "within an intent, a story waits only for the other's spec" 'met +S1: needs its spec merged; it.s building' "$I" deps g-two
outp 1 "unmet dependencies exit 1" 'UNMET +chatui-accounts: needs to ship; it.s reserved' "$I" deps g-three
outp 2 "an intent with stories asks for a story" 'name one: S1 g-one' "$I" deps gamma
outp 2 "an unknown slug" 'no intent or story' "$I" deps nope
outp 0 "a merged pull request is met" 'met +#10' env PATH="$SP/gh-merged:$PATH" "$I" deps beta
outp 1 "an open pull request isn't" 'UNMET +#10.*open' env PATH="$SP/gh-open:$PATH" "$I" deps beta
outp 0 "a folder path works as a slug" '2026-01-02-beta' env PATH="$SP/gh-merged:$PATH" "$I" deps intent/2026-01-02-beta
outp 0 "a story's folder path works as its slug" 'S2 g-two of 2026-01-03-gamma' "$I" deps intent/2026-01-03-gamma/g-two/
outp 1 "a story under a heading waits for its After" 'UNMET +S1: needs to ship' "$I" deps t-two

echo "== intents export"
# jx <exit> <label> <jq filter> <cmd...>: the command exits <exit> and the filter is true on its output.
jx() {
  local want=$1 label=$2 f=$3 o c; shift 3
  o=$("$@" 2>/dev/null); c=$?
  jq -e "$f" >/dev/null 2>&1 <<<"$o" || c="$c, false: $f"
  expect "$want" "$label" "$c"
}
mkdir -p intent/2026-01-05-theta/t-one
cat > intent/2026-01-05-theta/t-one/spec.md <<'EOF'
# Spec: Build rules visually

## 3. Acceptance criteria

| # | Given | When | Then |
|---|---|---|---|
| A1 (R1) | An analyst | saves a rule | it's listed |

## 4. Design
x
EOF
cat > intent/2026-01-05-theta/t-one/plan.md <<'EOF'
# Plan: Build rules visually

## 5. Order of work
1. **Rule model and API.** Tests: A1.
2. **The builder UI** *(riskiest step)*.

## 6. Risks
3. **Not a step.**
EOF
git add -A && at 2026-01-14 git commit -qm "docs(spec): t-one" && git push -q origin main && git fetch -q origin
T1='.intents[0].stories[0]'
jx 0 "export: an intent with stories is an epic" '.intents[0].epic.label == "sdlc:theta" and (.intents[0].epic.description | test("S2 Chain conditions"))' "$I" export theta
jx 0 "export: a story's title and label" "$T1.summary == \"S1 Build rules visually\" and $T1.label == \"sdlc:t-one\"" "$I" export theta
jx 0 "export: the description carries the story block" "$T1.description | test(\"Generated by sdlc-kit\") and test(\"What users get\") and test(\"  - Nested under it\")" "$I" export theta
jx 0 "export: a merged spec adds its acceptance table" "$T1.spec.acceptance | test(\"A1 \\\\(R1\\\\)\")" "$I" export theta
jx 0 "export: the acceptance table is in the description" "$T1.description | test(\"Acceptance tests\")" "$I" export theta
jx 0 "export: plan steps come from Order of work only" "$T1.plan.steps == [{n:1,title:\"Rule model and API\"},{n:2,title:\"The builder UI\"}]" "$I" export theta
jx 0 "export: a story's stage" "$T1.stage == \"planned\"" "$I" export theta
jx 0 "export: a dropped story is marked" '.intents[0].stories[2] | .dropped and .summary == "S3 Export rules"' "$I" export theta
jx 0 "export: After S1 ships blocks on shipping" '.intents[0].stories[1].blocked_by == [{ref:"S1",slug:"t-one",ships:true}]' "$I" export theta
jx 0 "export: After S1 within an intent waits for the spec" '.intents[0].stories[1].blocked_by == [{ref:"alpha",slug:"alpha",ships:true},{ref:"S1",slug:"g-one",ships:false}]' "$I" export gamma
jx 0 "export: another intent always has to ship" '.intents[0].stories[0].blocked_by == [{ref:"alpha",slug:"alpha",ships:true}]' "$I" export gamma
jx 0 "export: a one-line story's title" '.intents[0].stories[0].title == "the backend"' "$I" export gamma
jx 0 "export: a single-story intent has no epic" '.intents[0].epic == null and .intents[0].stories[0].slug == "alpha" and (.intents[0].stories[0].description | test("\\*\\*Problem\\*\\*"))' "$I" export alpha
jx 0 "export: a story slug exports its intent" '.intents[0].slug == "theta"' "$I" export t-two
jx 0 "export: with no slug, every merged intent" '[.intents[].slug] | index("epsilon") == null and length >= 6' "$I" export
jx 0 "export: the digest is stable" "$T1.digest == \"$("$I" export theta | jq -r "$T1.digest")\"" "$I" export theta
jx 0 "export: --base reads an earlier commit" "$T1.spec == null" "$I" export theta --base "$(git rev-parse HEAD~1)"
outp 1 "export: a draft isn't exported" "only merged intents" "$I" export epsilon
outp 2 "export: an unknown slug" 'no intent or story' "$I" export nope
jx 0 "export: links are file paths without a web remote" "$T1.spec.url == \"intent/2026-01-05-theta/t-one/spec.md\"" "$I" export theta
git remote set-url origin git@github.com:o/r.git
jx 0 "export: links point at the default branch on GitHub" "$T1.spec.url == \"https://github.com/o/r/blob/main/intent/2026-01-05-theta/t-one/spec.md\"" "$I" export theta
git remote set-url origin "$SP/ip-origin.git"

echo "== intents check: relations and layout"
outp 0 "a clean repo" 'no problems found' "$I" check
mkintent 2026-01-08-eta accepted "- **Supersedes:** delta\n"
outp 1 "Supersedes without flipping the old Status" 'Status of intent/2026-01-04-delta/intent.md to .superseded.' "$I" check
subst intent/2026-01-04-delta/intent.md "Status:** deferred" "Status:** ~~deferred~~ superseded"
outp 0 "Supersedes with the old Status flipped" 'no problems found' "$I" check
ireset
mkintent 2026-01-08-eta accepted "- **Supersedes:** \`intent/2026-01-07-epsilon\` (PR #9, never merged). Its points are folded in.\n"
outp 0 "superseding a draft, with a note, is allowed" 'no problems found' "$I" check
ireset
subst intent/2026-01-04-delta/intent.md "Status:** deferred" "Status:** superseded"
outp 0 "superseded with no successor is only a warning" 'warning: .*no intent says .Supersedes: delta.' "$I" check
ireset
subst intent/2026-01-03-gamma/intent.md "the backend. Outcomes: 1." "the backend. After: S2."
outp 1 "a cycle between stories" 'dependency cycle: g-one → g-two → g-one' "$I" check
ireset
subst intent/2026-01-02-beta/intent.md "Depends on:** #10" "Depends on:** zeta"
subst intent/2026-01-06-zeta/intent.md "Status:** accepted" "Status:** accepted
- **Depends on:** beta"
outp 1 "a cycle between intents" 'dependency cycle: beta → zeta → beta' "$I" check
ireset
mkintent 2026-01-09-alpha accepted
outp 1 "two intents with one slug" "the slug 'alpha' is also used by" "$I" check
ireset
subst intent/2026-01-03-gamma/intent.md "S2 g-two" "S2 beta"
outp 1 "a story slug that's an intent's slug" "the slug 'beta' is also used by" "$I" check
ireset
mkintent 2026-01-09-epsilon accepted
outp 1 "a slug a draft on another branch already uses" "also used by origin/docs/intent-epsilon:" "$I" check
ireset
subst intent/2026-01-02-beta/intent.md "#10" "a backend intent nobody has written yet"
outp 0 "Depends on written as a sentence is only a warning" 'warning: .*Depends on is written as a sentence' "$I" check
ireset
subst intent/2026-01-02-beta/intent.md "#10" "alpha, the backend work"
outp 1 "a ref list with an unreadable item" "can't read 'the backend work'" "$I" check
ireset
subst intent/2026-01-02-beta/intent.md "#10" "alpha,
  the backend work"
outp 1 "a value wrapped onto the next line is read whole" "can't read 'the backend work'" "$I" check
ireset
subst intent/2026-01-02-beta/intent.md "#10" "\`intent/2026-01-01-alpha\` (merged). The rest is a note."
outp 0 "a ref followed by a note" 'no problems found' "$I" check
ireset
subst intent/2026-01-02-beta/intent.md "#10" "S2"
outp 1 "Depends on naming a story id" "can't name a story id" "$I" check
ireset
subst intent/2026-01-03-gamma/intent.md "After: S1." "After: S9."
outp 1 "After naming a story that isn't there" 'has no story S9' "$I" check
ireset
subst intent/2026-01-05-theta/intent.md "**After:** S1 ships" "**After:** S9"
outp 1 "After under a story heading naming a story that isn't there" 'has no story S9' "$I" check
ireset
subst intent/2026-01-05-theta/intent.md "### S2 t-two" "### Notes on t-two"
outp 1 "a heading in Stories that isn't a story" "can't read this story's heading" "$I" check
ireset
subst intent/2026-01-06-zeta/intent.md "Status:** accepted" "Status:** done"
outp 1 "an unknown Status" "unknown Status 'done'" "$I" check
ireset
subst intent/2026-01-06-zeta/intent.md "Status:** accepted" "Status:** draft | accepted"
outp 1 "the template's Status left in" 'lists several values' "$I" check
ireset
echo s > intent/2026-01-03-gamma/spec.md
outp 1 "a spec at the top of an intent with stories" 'belongs in <story-slug>/spec.md' "$I" check
ireset
mkdir -p intent/2026-01-03-gamma/g-nine && echo s > intent/2026-01-03-gamma/g-nine/spec.md
outp 1 "a spec folder that isn't a story" "'g-nine' isn't a story" "$I" check
ireset
printf -- '- **Later.** → follow-up: TBD\n' >> intent/2026-01-02-beta/intent.md
outp 1 "a follow-up marker without a slug" 'follow-up marker needs a slug' "$I" check
ireset
subst intent/2026-01-03-gamma/intent.md "chatui-accounts" "alphaa"
outp 0 "a ref one typo away from a slug" "Did you mean 'alpha'" "$I" check
ireset
for n in 5 6 7; do printf -- '- **S%s g-x%s**: more.\n' "$n" "$n" >> intent/2026-01-03-gamma/intent.md; done
outp 0 "more than five stories is a warning" 'warning: .*6 stories' "$I" check
ireset

echo "== intents check: prose that promises later work"
printf -- '\n- **Purging.** Purging old data is a follow-up intent.\n' >> intent/2026-01-02-beta/intent.md
outp 0 "prose without a marker warns, never fails" 'warning: intent/2026-01-02-beta/intent.md:13: .follow-up intent. promises later work' "$I" check
outp 0 "check <file> reports that file" 'beta/intent.md:13' "$I" check intent/2026-01-02-beta/intent.md
outn 0 "check <file> skips other files" 'beta/intent.md' "$I" check intent/2026-01-01-alpha/intent.md
ireset
printf -- '\n- **Purging.** Purging old data is a follow-up intent. → follow-up: purge\n' >> intent/2026-01-02-beta/intent.md
outn 0 "prose with a marker in the same item" 'warning' "$I" check
ireset
printf -- '\n- ~~**Purging.** Purging old data is a follow-up intent.~~ (Amended: dropped.)\n' >> intent/2026-01-02-beta/intent.md
outn 0 "struck-through prose" 'warning' "$I" check
ireset
printf -- '\nWrite `a separate intent` for it.\n' >> intent/2026-01-02-beta/intent.md
outn 0 "prose inside code" 'warning' "$I" check
ireset

echo "== intents check: translated keywords"
# Heredocs, not subst: subst's python reads with the locale's encoding, which can't take Arabic everywhere.
mkdir -p intent/2026-01-15-iota intent/2026-01-15-kappa intent/2026-01-15-lambda intent/2026-01-15-mu
cat > intent/2026-01-15-iota/intent.md <<'EOF'
# Intent: iota

- **Author:** t
- **Status:** accepted

## Problem
x

## القصص
### S1 i-one: The backend
- **Outcomes:** 1
EOF
cat > intent/2026-01-15-kappa/intent.md <<'EOF'
# Intent: kappa

- **Author:** t
- **Status:** accepted
- **يعتمد على:** chat-login
- **Language:** ar
- **Review doc:** https://example.com/d

## Problem
x

## Desired outcome
1. x

## stories
### S1 k-one: The backend
- **Outcomes:** ١، ٢

### S2 k-two: The chat window
- **بعد:** S1

### S١ k-three: Chat window
- **Outcomes:** 1

## Out of scope
- x
EOF
cat > intent/2026-01-15-lambda/intent.md <<'EOF'
# Intent: lambda

- **Author:** t
- **Status:** accepted

## Stories
### S1 l-one: One
- **Outcomes:** 1

### S2 l-two: Two
- **Outcomes:** 1

### S3 l-three: Three
- **After:** S1، S2
EOF
cat > intent/2026-01-15-mu/intent.md <<'EOF'
# Intent: mu

- **Author:** t
- **Date:** 2026-01-15
- **Status:** accepted
- **Approved by:** t
- **Language:** ar
- **Review doc:** https://example.com/d

## Problem
## Desired outcome
## Where we are today
## stories
### S1 mu-one: One
- **Outcomes:** 1
- **Actors:** t
- **User story:** As a t, I want x, so y.

### S2 mu-two: Two
- **After:** S1
## Users affected
## Systems affected
## Constraints
## Out of scope
## Open questions
## Decisions
## Evidence
EOF
K=intent/2026-01-15-kappa/intent.md
outp 0 "a translated Stories heading warns" 'warning: intent/2026-01-15-iota/intent.md:9: .*## Stories' "$I" check intent/2026-01-15-iota/intent.md
outn 0 "template headings in any case don't warn" 'heading' "$I" check intent/2026-01-15-mu/intent.md
outp 0 "an unknown header field warns with the known list" "warning: $K:5: .*Author, Date, Status, Approved by, Revisit, Depends on, Supersedes, Review doc, Language" "$I" check $K
outn 0 "Language and Review doc are known header fields" 'header field' "$I" check intent/2026-01-15-mu/intent.md
outp 0 "an unknown story field warns with the story fields" "warning: $K:20: .*Outcomes, After, Actors, User story" "$I" check $K
outp 0 "Arabic-Indic digits in a story heading warn" "warning: $K:22: .*### S1 k-three" "$I" check $K
outp 0 "an Arabic comma in Outcomes warns" "warning: $K:17: .*1, 2" "$I" check $K
outp 1 "an Arabic comma in After warns next to the error" 'warning: intent/2026-01-15-lambda/intent.md:14: .*S1, S2' "$I" check intent/2026-01-15-lambda/intent.md
outp 1 "an Arabic comma in After is still an error" "error: intent/2026-01-15-lambda/intent.md:13: can't read 'S1" "$I" check intent/2026-01-15-lambda/intent.md
outp 0 "the hook passes keyword warnings as context" 'additionalContext.*header field' ih "$(iwrite $K)"
mkdir -p intent/2026-01-15-xi
cat > intent/2026-01-15-xi/intent.md <<'EOF'
# Intent: xi

- **Author:** t
- **Status:** accepted

## Stories
### S1 x-one: One
- **Outcomes:** 1

### S2 x-two: Two
- **after:** S1
EOF
outp 0 "a lowercase story field warns, since After: is read only as written" 'warning: intent/2026-01-15-xi/intent.md:11: .*Outcomes, After, Actors, User story' "$I" check intent/2026-01-15-xi/intent.md
mkdir -p intent/2026-01-15-nu
sed 's/draft | accepted | deferred | rejected | superseded/draft/' "$KIT/templates/intent-TEMPLATE.md" > intent/2026-01-15-nu/intent.md
outp 0 "the template's English keywords give no new output" 'no problems found' "$I" check intent/2026-01-15-nu/intent.md
git add intent/2026-01-15-iota intent/2026-01-15-kappa && git commit -qm "docs(intent): translated keywords"
outp 0 "a translated Stories heading is still read as one story" '2026-01-15-iota +accepted' "$I" status --base HEAD
outn 0 "a story under a translated Stories heading is still not read" 'i-one' "$I" status --base HEAD
outp 0 "a translated After still gives no dependencies" 'no dependencies' "$I" deps k-two --base HEAD
outp 0 "a story id with Arabic-Indic digits is still read" 'k-three +accepted' "$I" status --base HEAD
git reset -q --hard HEAD~1
ireset

echo "== intents hook (PostToolUse)"
B=intent/2026-01-02-beta/intent.md
outn 0 "a file outside intent/ is ignored" . ih "$(iedit README.md 'a separate intent')"
printf -- '\n- **Purging.** Purging old data is a follow-up intent.\n' >> $B
outp 0 "an edit that adds prose adds context" 'additionalContext.*follow-up intent' ih "$(iedit $B '- **Purging.** Purging old data is a follow-up intent.')"
outn 0 "an edit elsewhere doesn't repeat old warnings" . ih "$(iedit $B '## Problem')"
outp 0 "a Write checks the whole file" 'additionalContext' ih "$(iwrite $B)"
ireset
subst $B "#10" "S2"
outp 2 "an edit that leaves an error goes to Claude" "can't name a story id" ih "$(iedit $B 'S2')"
ireset
outn 0 "a skill that isn't a policy is ignored" . ih "$(iwrite .claude/skills/helper/SKILL.md)"
printf -- '\nThe gateway is tracked as a separate intent.\n' >> .claude/skills/api-security/SKILL.md
outp 0 "a policy skill is checked" 'additionalContext.*separate intent' ih "$(iedit .claude/skills/api-security/SKILL.md 'The gateway is tracked as a separate intent.')"
ireset
subst $B "#10" "S2"
CLAUDE_PROJECT_DIR=/nonexistent hook 2 "the repo comes from the file, not CLAUDE_PROJECT_DIR" "$IH" "$(iedit $B 'S2')"
ireset
cd "$SP" || exit 1

echo "== $pass passed, $fail failed"
[[ $fail -eq 0 ]]
