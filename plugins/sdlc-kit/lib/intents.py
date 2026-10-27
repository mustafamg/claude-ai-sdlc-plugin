#!/usr/bin/env python3
"""Intents, stories and the relations between them, for the sdlc-kit. Run through bin/intents.

  intents status [<slug>]    each intent and story with the stage it has reached, drafts that exist
                             only on docs/intent-* branches, and reserved slugs (named, not written)
  intents check [<file>...]  relation and layout errors (exit 1) and warnings, for the whole repo or
                             only the named files
  intents deps <slug>        whether a story's (or a single-story intent's) dependencies are met;
                             exit 1 if any isn't
  intents export [<slug>]    JSON for a tracker sync (Jira): the intent, or every merged intent, with
                             each story's title, a ready-made description and its digest, what it's
                             blocked by, its stage, and its spec's acceptance table and plan's steps
                             once they're merged
  intents hook               PostToolUse mode: reads the hook JSON on stdin and checks the file written
Options: --base <ref> picks the default branch (else $INTENTS_BASE, origin/HEAD, origin/main,
origin/master, main, master). Nothing here fetches: run `git fetch` first to see others' drafts.

What it reads:
  Header fields, in the bullet list above intent.md's first `## ` heading:
    - **Status:** draft | accepted | deferred | rejected | superseded
    - **Depends on:** <ref>, <ref>      every story of this intent waits for each one to ship
    - **Supersedes:** <slug>            the old intent's Status must say `superseded`, same change
    A note may follow the refs, in parentheses or after a full stop.
  An optional `## Stories` section, one `###` heading per story, its lines running to the next one:
    ### S1 <story-slug>: <title>
    - **After:** S2, other-slug ships
    or, the older form, one list item per story:
    - **S1 <story-slug>**: what ships. Outcomes: 1, 3. After: S2, other-slug ships.
    `After:` naming a story of the same intent waits for that story's spec to merge, or for it to
    ship when followed by ` ships`. Other intents, their stories and #N always have to ship. A story
    whose heading or line is struck through (`### ~~S3 slug: ...~~`, `- ~~**S3 slug**: ...~~`) was
    dropped by amendment. Without a Stories section the intent is a single story, and its spec.md and
    plan.md sit in the intent folder.
  A follow-up marker anywhere in intent/<folder>/**.md or a policy skill:
    -> follow-up: <slug>   (or the arrow →). The slug stays reserved until an intent or story uses it.
  A ref is a slug (an intent folder's name without its date, or a story's slug), a story id (S2) of
  the same intent, or #N (a pull request or issue, checked with gh).
  Keywords stay in English. A `## ` heading that isn't one of the template's, a header or story field
  intents doesn't know, and Eastern Arabic-Indic digits or `،` in a structural line get a warning,
  since a translated keyword would otherwise be skipped without a word.

Stages are derived, never declared: reserved; draft (the intent is only on a branch or in the working
tree); the intent's Status; specced and planned (spec.md / plan.md on the default branch); building
(`test(<slug>): step N` or `feat(<slug>): step N` commits on any branch); shipped (a `feat(<slug>):
step N` commit reachable from the default branch, including `* feat(...)` lines in a squash-merge
body). An intent with stories has shipped once every story that wasn't dropped has.
"""
from __future__ import annotations

import functools
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from typing import NamedTuple

SLUG = r"[a-z0-9][a-z0-9-]*"
SLUG_RE = re.compile(SLUG)
DATED = re.compile(r"\d{4}-\d{2}-\d{2}-(" + SLUG + r")")
STORY_ID = re.compile(r"S\d+")
STATUSES = ("draft", "accepted", "deferred", "rejected", "superseded")
SPEC_OR_LATER = ("specced", "planned", "building", "shipped")
MAX_STORIES = 5

HEADER_FIELD = re.compile(r"^\s*[-*]\s+\*\*(?P<key>[^*:]+):\*\*\s*(?P<val>.*)$")
STORIES_HEADING = re.compile(r"^##\s+stories\s*$", re.I)
# The template's headings and the fields intents knows. Anything else is skipped, so a translated
# keyword gets a warning naming the English ones.
HEADINGS = ("Problem", "Desired outcome", "Where we are today", "Stories", "Users affected",
            "Systems affected", "Constraints", "Out of scope", "Open questions", "Decisions", "Evidence")
HEADER_FIELDS = ("Author", "Date", "Status", "Approved by", "Revisit", "Depends on", "Supersedes",
                 "Review doc", "Language")
STORY_FIELDS = ("Outcomes", "After", "Actors", "User story")
STORY_REFS = re.compile(r"\b(?:After|Outcomes):")
# Eastern Arabic-Indic digits and the Arabic comma, which intents doesn't read as 0-9 and `,`.
ARABIC = re.compile("[٠-٩،]")
TO_ASCII = str.maketrans("٠١٢٣٤٥٦٧٨٩،", "0123456789,")
BULLET = re.compile(r"^ {0,3}[-*+]\s+")
ITEM = re.compile(r"^ {0,3}(?:[-*+]|\d+[.)])\s+")
STORY_HEADING = re.compile(r"^###\s+(?P<strike>~~)?(?P<sid>S\d+)\s+(?P<slug>[^\s:*~]+)(?P<rest>.*)$")
STORY = re.compile(r"^ {0,3}[-*+]\s+(?P<strike>~~)?\*\*(?P<sid>S\d+)\s+(?P<slug>[^*\s]+)\*\*(?P<rest>.*)$")
AFTER = re.compile(r"(?:\*\*|\*|_)?\bAfter:(?:\*\*|\*|_)?[ \t]*(?P<refs>[^.;\n]*)")
MARKER = re.compile(r"(?:→|->)\s*follow-up:\s*(?P<val>.*)", re.I)
MARKER_REFS = re.compile(r"\s*(" + SLUG + r"(?:\s*,\s*" + SLUG + r")*)")
STEP_GREP = r"^(\* )?(test|feat)\(([a-z0-9-]+)\): step [0-9]+"
STEP = re.compile(STEP_GREP, re.M)
DRAFT_REF = re.compile(r"refs/(?:remotes/[^/]+|heads)/docs/intent-")
# Fenced code and HTML comments, blanked before anything is parsed (newlines kept, so line numbers hold).
BLANKED = re.compile(r"^[ \t]*(```|~~~).*?(?:^[ \t]*\1[^\n]*|\Z)|<!--.*?(?:-->|\Z)", re.S | re.M)
STRIKE = re.compile(r"~~.*?~~")
CODE = re.compile(r"`[^`]*`")
# Prose that promises work for later. Matched only outside code and struck-through text, and never in
# a list item or paragraph that already carries a follow-up marker.
PROSE = re.compile(
    r"\b(?:separate|later|future|follow[- ]?up|own|another) (?:intent|story)\b"
    r"|\b(?:in|as) a follow[- ]?up\b|\bfast[- ]follow\b",
    re.I,
)


class Problem(NamedTuple):
    path: str
    line: int
    level: str  # "error" or "warning"
    msg: str

    def __str__(self):
        return f"{self.level}: {self.path}:{self.line}: {self.msg}"


def err(where, line, msg):
    return Problem(where, line, "error", msg)


def warn(where, line, msg):
    return Problem(where, line, "warning", msg)


class Ref(NamedTuple):
    ref: str  # a slug, a story id (S2) or #N
    ships: bool
    line: int


@dataclass(eq=False)
class Unit:
    """Specced, planned, built and shipped on its own: a story, or a single-story intent."""
    slug: str
    intent: Intent
    sid: str | None = None
    line: int = 1
    dropped: bool = False
    after: list = field(default_factory=list)


@dataclass(eq=False)
class Intent:
    folder: str
    where: str  # its intent.md, prefixed with the branch for a draft read from one
    slug: str
    status: str | None = None
    status_line: int = 1
    revisit: str = ""
    depends: list = field(default_factory=list)
    supersedes: list = field(default_factory=list)
    units: list = field(default_factory=list)
    stories_line: int = 1

    @property
    def path(self):
        return f"intent/{self.folder}/intent.md"

    @property
    def has_stories(self):
        return self.units[0].sid is not None

    @property
    def live(self):
        return [u for u in self.units if not u.dropped]


# ---------------------------------------------------------------- parsing

def clean_lines(text):
    return BLANKED.sub(lambda m: "\n" * m.group(0).count("\n"), text).split("\n")


def scan_lines(text):
    """Lines to search for markers and prose: also without inline code or struck-through text."""
    return [STRIKE.sub("", CODE.sub("", line)) for line in clean_lines(text)]


def plain(s):
    return STRIKE.sub("", s).replace("`", "").replace("*", "")


def normalize(tok):
    """A work folder's name or path (an intent folder, or a story's folder inside one) reduced to its
    slug; anything else comes back unchanged."""
    tok = tok.strip().strip("/").removeprefix("intent/").removesuffix("/intent.md").rsplit("/", 1)[-1]
    m = DATED.fullmatch(tok)
    return m.group(1) if m else tok


def parse_refs(val, line, ships=False):
    """Refs at the start of a field value, and the tokens that aren't refs. A note may follow in
    parentheses or after a full stop; an unfilled template placeholder (`<...>`) reads as none."""
    v = re.sub(r"\([^)]*\)", "", plain(re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", val)))
    v = re.split(r"\.(?:\s|$)", v, maxsplit=1)[0].strip()
    if not v or "<" in v or v.lower() in ("none", "n/a", "-", "—", "–"):
        return [], []
    refs, bad = [], []
    for tok in filter(None, (t.strip() for t in re.split(r"\s*,\s*|\s+and\s+", v))):
        m = re.fullmatch(r"(.+?)\s+ships", tok)
        tok = normalize(m.group(1) if m else tok)
        if STORY_ID.fullmatch(tok) or re.fullmatch(r"#\d+", tok) or SLUG_RE.fullmatch(tok):
            refs.append(Ref(tok, ships or bool(m), line))
        else:
            bad.append(tok)
    return refs, bad


def arabic_digits(where, n, line):
    """A warning, with the line's ASCII form, if a structural line has Arabic-Indic digits or `،`."""
    if not ARABIC.search(line):
        return []
    return [warn(where, n, "Eastern Arabic-Indic digits and `،` aren't read as numbers or separators; "
                           f"write `{line.strip().translate(TO_ASCII)}`")]


def unknown_field(where, n, kind, name, known):
    # Header fields are read in any case; `After:` only as written, so story fields must match exactly.
    if (name.lower() in (k.lower() for k in known)) if kind == "header" else name in known:
        return []
    return [warn(where, n, f"the {kind} field {name!r} isn't one intents reads, so it's skipped. Keep "
                           f"field names in English: {', '.join(known)}")]


def parse_intent(folder, where, text):
    """An Intent read from its intent.md, and the problems found reading it."""
    it, probs = Intent(folder, where, normalize(folder)), []
    if not SLUG_RE.fullmatch(it.slug):
        probs.append(err(where, 1, f"the folder name {folder!r} doesn't give a usable slug: use "
                                   "YYYY-MM-DD-<slug>, with lowercase letters, digits and hyphens"))
    fields, stories, current, section, headed = [], [], None, "header", False
    for n, line in enumerate(clean_lines(text), 1):
        if line.startswith("## "):
            section, current = ("stories" if STORIES_HEADING.match(line) else "body"), None
            if section == "stories":
                it.stories_line, headed = n, False
            elif line[3:].strip().lower() not in (h.lower() for h in HEADINGS):
                probs.append(warn(where, n, f"`{line.strip()}` isn't one of the template's headings, so "
                                            "it's read as text. Keep headings in English: "
                                            f"{', '.join('## ' + h for h in HEADINGS)}"))
        elif section == "header":
            fm = HEADER_FIELD.match(line)
            if fm:
                fields.append([fm.group("key").strip(), fm.group("val"), n])
                probs += unknown_field(where, n, "header", fm.group("key").strip(), HEADER_FIELDS)
                probs += arabic_digits(where, n, line)
            elif fields and line.strip() and not BULLET.match(line):
                fields[-1][1] += " " + line.strip()  # a value wrapped onto the next line
        elif section == "stories" and line.startswith("### "):
            sm, current, headed = STORY_HEADING.match(line), None, True
            probs += arabic_digits(where, n, line)
            if not sm:
                probs.append(err(where, n, "can't read this story's heading: write `### S1 <story-slug>: "
                                           "<title>`"))
            else:
                current = [Unit(sm.group("slug"), it, sm.group("sid"), n, bool(sm.group("strike"))),
                           sm.group("rest")]
                if "<" not in sm.group("slug"):  # not an unfilled template heading
                    stories.append(current)
        elif section == "stories" and headed:
            if current:  # every line up to the next heading belongs to the story
                current[1] += "\n" + line
                fm = HEADER_FIELD.match(line)
                if fm:
                    probs += unknown_field(where, n, "story", fm.group("key").strip(), STORY_FIELDS)
                if STORY_REFS.search(line):
                    probs += arabic_digits(where, n, line)
        elif section == "stories":
            if BULLET.match(line):
                sm, current = STORY.match(line), None
                if sm or STORY_REFS.search(line):
                    probs += arabic_digits(where, n, line)
                if not sm:
                    probs.append(err(where, n, "can't read this story: write `- **S1 <story-slug>**: "
                                               "what ships. Outcomes: 1, 2. After: S2.`"))
                elif "<" not in sm.group("slug"):  # not an unfilled template line
                    current = [Unit(sm.group("slug"), it, sm.group("sid"), n, bool(sm.group("strike"))),
                               sm.group("rest")]
                    stories.append(current)
            elif current and line.strip() and line[:1].isspace():
                current[1] += " " + line.strip()
            else:
                current = None
    seen_status = False
    for name, val, n in fields:
        key = name.lower()
        if key == "status":
            seen_status, it.status_line, raw = True, n, plain(val)
            if "|" in raw:
                probs.append(err(where, n, "Status lists several values; keep the one that applies"))
                continue
            w = re.match(r"\s*([A-Za-z]+)", raw)
            it.status = w.group(1).lower() if w else None
            if it.status not in STATUSES:
                probs.append(err(where, n, f"unknown Status {it.status or raw.strip()!r}; use one of "
                                           f"{', '.join(STATUSES)}"))
        elif key == "revisit":
            r = re.search(r"\d{4}-\d{2}", val)
            it.revisit = r.group(0) if r else ""
        elif key in ("depends on", "supersedes"):
            refs, bad = parse_refs(val, n, ships=True)
            if bad and not refs and any(" " in b for b in bad):
                probs.append(warn(where, n, f"{name} is written as a sentence, so nothing can check it. "
                                            "Name intents and stories by slug, or pull requests as #N; "
                                            "a note can follow in parentheses or after a full stop."))
                continue
            probs += [err(where, n, f"can't read {b!r} in {name}: name an intent or story by its slug, "
                                    "or a pull request as #N, separated by commas") for b in bad]
            (it.depends if key == "depends on" else it.supersedes).extend(refs)
    if not seen_status:
        probs.append(err(where, 1, "no `- **Status:**` line in the header"))
    sids = set()
    for unit, rest in stories:
        if not SLUG_RE.fullmatch(unit.slug):
            probs.append(err(where, unit.line, f"story slug {unit.slug!r} must be lowercase letters, "
                                               "digits and hyphens"))
        if unit.sid in sids:
            probs.append(err(where, unit.line, f"two stories are numbered {unit.sid}"))
        sids.add(unit.sid)
        for am in AFTER.finditer(rest) if not unit.dropped else ():
            refs, bad = parse_refs(am.group("refs"), unit.line)
            probs += [err(where, unit.line, f"can't read {b!r} after `After:`: name S2, a slug, or #N, "
                                            "separated by commas, with ` ships` to wait for a story of "
                                            "this intent to ship") for b in bad]
            unit.after += refs
    it.units = [u for u, _ in stories] or [Unit(it.slug, it)]
    return it, probs


def is_policy(text):
    m = re.match(r"---\n(.*?)\n---", text, re.S)
    d = m and re.search(r"^description:\s*['\"]?(.*)$", m.group(1), re.M)
    return bool(d and d.group(1).startswith("Policy -"))


def scannable(path):
    return bool(re.fullmatch(r"intent/[^/]+/(?:[^/]+/)*[^/]+\.md", path)
                or re.fullmatch(r"\.claude/skills/[^/]+/SKILL\.md", path))


def folder_of(path):
    m = re.match(r"intent/([^/]+)/", path)
    return m.group(1) if m else None


# ---------------------------------------------------------------- git

def run_git(root, *args):
    r = subprocess.run(["git", "-C", root, *args], capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else None


def short(ref):
    return re.sub(r"^refs/(?:heads|remotes)/", "", ref)


def decode(data):
    return data.decode("utf-8", "replace").replace("\r\n", "\n")


def tree_entries(sha, data):
    """(mode, name) for each entry of a raw git tree object."""
    out, i, width = [], 0, len(sha) // 2
    while i < len(data):
        sp, nul = data.index(b" ", i), data.index(b"\0", i)
        out.append((data[i:sp].decode(), decode(data[sp + 1:nul])))
        i = nul + 1 + width
    return out


class Repo:
    def __init__(self, root, base=None):
        self.root = root
        refs = [r.split("\0") for r in (self.git("for-each-ref", "--format=%(refname)%00%(tree)%00%(symref)",
                                                 "refs/remotes", "refs/heads") or "").splitlines()]
        trees = {name: tree for name, tree, _ in refs}
        head = next((sym for name, _, sym in refs if name == "refs/remotes/origin/HEAD"), "")
        candidates = (head, "refs/remotes/origin/main", "refs/remotes/origin/master", "refs/heads/main",
                      "refs/heads/master")
        self.base = (base or os.environ.get("INTENTS_BASE")
                     or next((short(r) for r in candidates if r in trees), "HEAD"))
        # One docs/intent-* branch per distinct tree, remotes first: a branch and its pushed copy are
        # read once.
        seen, self.draft_refs = set(), []
        for ref in sorted(trees, key=lambda r: (not r.startswith("refs/remotes/"), r)):
            if DRAFT_REF.match(ref) and trees[ref] not in seen:
                seen.add(trees[ref])
                self.draft_refs.append(ref)
        out = self.git("ls-tree", "-r", "--name-only", self.base, "--", "intent", ".claude/skills") or ""
        self.base_paths = set(out.split("\n")) - {""}
        self.base_folders = {folder_of(p) for p in self.base_paths} - {None}

    def git(self, *args):
        return run_git(self.root, *args)

    @functools.cached_property
    def web(self):
        """The browsable https URL of origin, or "" when it isn't a GitHub-style remote."""
        url = (self.git("remote", "get-url", "origin") or "").strip()
        m = re.fullmatch(r"(?:https?://|ssh://)?(?:[^@/]+@)?([^/:]+)[:/](.+?)(?:\.git)?/?", url)
        if not m or "." not in m.group(1):
            return ""
        # An ssh host alias for a second account (github.com-work) is still that host.
        host = re.sub(r"^(github\.com|gitlab\.com|bitbucket\.org)\b.*", r"\1", m.group(1))
        return f"https://{host}/{m.group(2)}"

    def cat(self, specs):
        """Many objects read in one git call: {spec: (sha, type, data)}. Missing ones are left out."""
        if not specs:
            return {}
        data = subprocess.run(["git", "-C", self.root, "cat-file", "--batch"],
                              input="".join(s + "\n" for s in specs).encode(), capture_output=True).stdout
        out, pos = {}, 0
        for spec in specs:
            nl = data.find(b"\n", pos)
            if nl < 0:
                break
            header, pos = data[pos:nl].split(), nl + 1
            if not header[-1].isdigit():  # missing or ambiguous
                continue
            size = int(header[-1])
            out[spec] = (header[0], header[1].decode(), data[pos:pos + size])
            pos += size + 1
        return out

    def blobs(self, rev, paths):
        got = self.cat([f"{rev}:{p}" for p in paths])
        return {p: decode(got[f"{rev}:{p}"][2]) for p in paths if f"{rev}:{p}" in got}

    def drafts(self, skip):
        """{path: (text, ref)} for each intent.md on a docs/intent-* branch whose folder isn't in skip,
        read from the first branch that has the folder."""
        trees, found = self.cat([f"{r}:intent" for r in self.draft_refs]), {}
        for ref in self.draft_refs:
            sha, kind, data = trees.get(f"{ref}:intent", (b"", "", b""))
            for mode, name in tree_entries(sha, data) if kind == "tree" else ():
                if mode == "40000" and name not in skip:
                    found.setdefault(f"intent/{name}/intent.md", ref)
        got = self.cat([f"{ref}:{p}" for p, ref in found.items()])
        return {p: (decode(got[f"{ref}:{p}"][2]), ref) for p, ref in found.items() if f"{ref}:{p}" in got}

    def worktree_paths(self):
        found = []
        for top in ("intent", ".claude/skills"):
            for dirpath, dirnames, filenames in os.walk(os.path.join(self.root, top)):
                dirnames[:] = [d for d in dirnames if not d.startswith(".")]
                found += [os.path.relpath(os.path.join(dirpath, f), self.root).replace(os.sep, "/")
                          for f in filenames]
        return sorted(p for p in found if scannable(p))

    def read_worktree(self, rel):
        with open(os.path.join(self.root, rel), encoding="utf-8", errors="replace") as f:
            return f.read().replace("\r\n", "\n")


@functools.lru_cache(None)
def added_on(root, ref, path):
    """The date path was first added on ref."""
    dates = (run_git(root, "log", ref, "--diff-filter=A", "--format=%cs", "--", path) or "").split()
    return dates[-1] if dates else ""


@functools.lru_cache(None)
def pr_state(root, ref):
    """(met, name, what it needs, what it is) for a #N ref, asked of gh."""
    gh = shutil.which("gh")
    if not gh:
        return False, ref, "to be merged", "unknown without gh"
    for kind in ("pr", "issue"):
        try:
            r = subprocess.run([gh, kind, "view", ref[1:], "--json", "state", "-q", ".state"],
                               cwd=root, capture_output=True, text=True, timeout=30)
        except (OSError, subprocess.TimeoutExpired):
            break
        if r.returncode == 0 and r.stdout.strip():
            st = r.stdout.strip().lower()
            if kind == "pr":
                return st == "merged", ref, "to be merged", f"{st} (pull request)"
            return st == "closed", ref, "to be closed", f"{st} (issue)"
    return False, ref, "to be merged", "not found by gh"


class History:
    """Step commits, and the date each file reached the default branch (the merge of its pull
    request, on the first-parent line, not the commit on the branch)."""

    def __init__(self, repo):
        self.started, self.shipped, self.added = {}, {}, {}
        log = repo.git("log", "--all", "-E", f"--grep={STEP_GREP}", "--format=%H%x1f%cs%x1f%B%x1e") or ""
        on_base = set((repo.git("log", repo.base, "-E", f"--grep={STEP_GREP}", "--format=%H") or "").split())
        for rec in filter(None, (r.strip("\n") for r in log.split("\x1e"))):
            h, date, body = rec.split("\x1f", 2)
            for _, kind, slug in STEP.findall(body):
                self.started[slug] = min(date, self.started.get(slug, date))
                if kind == "feat" and h in on_base:
                    self.shipped[slug] = max(date, self.shipped.get(slug, date))
        out = repo.git("log", repo.base, "--first-parent", "-m", "--diff-filter=A", "--name-only",
                       "--format=%x1e%cs", "--", "intent") or ""
        for rec in out.split("\x1e"):
            lines = [x for x in rec.split("\n") if x.strip()]
            for f in lines[1:]:
                self.added.setdefault(f, lines[0])


# ---------------------------------------------------------------- the model

class Model:
    """Every intent the repo knows about. view="worktree" (check, hook) reads files as they are on
    disk; view="base" (status, deps) reads merged intents from the default branch, so only what was
    approved counts. Either way, intents only on docs/intent-* branches are drafts."""

    def __init__(self, repo, view):
        self.repo = repo
        wt = {p: repo.read_worktree(p) for p in repo.worktree_paths()}
        base = repo.blobs(repo.base, sorted(p for p in repo.base_paths
                                            if scannable(p) and (view == "base" or p not in wt)))
        if view == "worktree":
            texts = {**base, **wt}
        else:
            texts = {**{p: t for p, t in wt.items() if folder_of(p) not in repo.base_folders}, **base}
        self.texts = {p: t for p, t in texts.items() if folder_of(p) or is_policy(t)}
        self.branch = {}  # folder -> the docs/intent-* branch a draft was read from
        skip = {folder_of(p) for p in self.texts} | repo.base_folders
        for path, (text, ref) in repo.drafts(skip).items():
            self.texts[path] = text
            self.branch[folder_of(path)] = ref
        self.local = [p for p in sorted(self.texts) if folder_of(p) not in self.branch]
        self.intents, self.problems = [], []
        for path in sorted(self.texts):
            m = re.fullmatch(r"intent/([^/]+)/intent\.md", path)
            if m:
                it, probs = parse_intent(m.group(1), self.where(path), self.texts[path])
                self.intents.append(it)
                self.problems += probs
        self.nodes = {}  # slug -> the intents with stories, stories and single-story units using it
        for it in self.intents:
            for n in [it, *it.units] if it.has_stories else it.units:
                self.nodes.setdefault(n.slug, []).append(n)
        self.successor = {}
        for it in self.intents:
            for r in it.supersedes:
                self.successor.setdefault(r.ref, it.slug)
        self.promises = {}  # slug -> [(path, line)] of its follow-up markers
        for path, text in sorted(self.texts.items()):
            for n, line in enumerate(scan_lines(text), 1):
                for mm in MARKER.finditer(line):
                    rm = MARKER_REFS.match(mm.group("val"))
                    if not rm:
                        self.problems.append(err(self.where(path), n, "a follow-up marker needs a slug: "
                                                 "`→ follow-up: <slug>`, lowercase letters, digits and hyphens"))
                    for s in re.split(r"\s*,\s*", rm.group(1)) if rm else ():
                        self.promises.setdefault(s, []).append((path, n))

    def where(self, path):
        ref = self.branch.get(folder_of(path))
        return f"{short(ref)}:{path}" if ref else path

    def place(self, it):
        if it.folder in self.repo.base_folders:
            return ""
        ref = self.branch.get(it.folder)
        return f"on {short(ref)}" if ref else "in the working tree"

    def resolve(self, it, ref):
        """The Unit or Intent a ref names, or None: reserved, or a pull request."""
        if STORY_ID.fullmatch(ref):
            return next((u for u in it.units if u.sid == ref), None)
        return next(iter(self.nodes.get(ref, [])), None)

    def names_nothing(self, it, r):
        return SLUG_RE.fullmatch(r.ref) and self.resolve(it, r.ref) is None

    def node(self, slug):
        """(the intent a slug names, directly or through one of its stories; the node itself)."""
        n = next(iter(self.nodes.get(slug, [])), None)
        return (n if isinstance(n, Intent) else n.intent if n else None), n

    # ------------------------------------------------------------ checks

    def check(self):
        """Relation and layout problems in this checkout's files (not in drafts on other branches)."""
        found = {*self.problems, *self._duplicates(), *self._refs(), *self._supersedes(), *self._cycles(),
                 *self._layout()}
        return sorted(p for p in found if p.path in self.local)

    def _duplicates(self):
        for slug, nodes in self.nodes.items():
            for n in nodes if len(nodes) > 1 else ():
                where, line, _ = owner(n)
                others = "; ".join(owner(o)[2] for o in nodes if o is not n)
                yield err(where, line, f"the slug {slug!r} is also used by {others}. Slugs name branches "
                                       "and commits, so each intent and story needs its own")

    def _refs(self):
        import difflib
        names = sorted(self.nodes)
        for it in self.intents:
            sids = {u.sid for u in it.units}
            for r in it.depends:
                if STORY_ID.fullmatch(r.ref):
                    yield err(it.where, r.line, f"Depends on can't name a story id ({r.ref}); put it under "
                                                "that story's `After:`")
            for u in it.live:
                for r in u.after:
                    if STORY_ID.fullmatch(r.ref) and r.ref not in sids:
                        yield err(it.where, r.line, f"`After:` names {r.ref}, but this intent has no story "
                                                    f"{r.ref}")
                    elif r.ref in (u.sid, u.slug):
                        yield err(it.where, r.line, f"{u.sid} can't come after itself")
                    elif r.ref == it.slug and it.has_stories:
                        yield err(it.where, r.line, f"{u.sid} can't wait for its own intent; name the story "
                                                    "it waits for")
            for r in it.depends + [r for u in it.units for r in u.after]:
                close = self.names_nothing(it, r) and difflib.get_close_matches(r.ref, names, n=1, cutoff=0.8)
                if close:
                    yield warn(it.where, r.line, f"{r.ref!r} isn't an intent or story yet, so it's reserved. "
                                                 f"Did you mean {close[0]!r}?")

    def _supersedes(self):
        for it in self.intents:
            for r in it.supersedes:
                target, n = self.node(r.ref)
                if not SLUG_RE.fullmatch(r.ref):
                    msg = "Supersedes names an intent by its slug"
                elif isinstance(n, Unit) and n.sid:
                    msg = (f"{r.ref} is a story; drop it from its intent's Stories list by amendment "
                           "instead of superseding it")
                elif target is None:
                    msg = f"there's no intent {r.ref!r} to supersede"
                elif self.state(target) != "superseded":  # a draft folded in counts as superseded
                    msg = (f"set the Status of {target.path} to `superseded` in this same change, with an "
                           f"amendment note naming {it.slug}")
                else:
                    continue
                yield err(it.where, r.line, msg)
            if it.status == "superseded" and it.slug not in self.successor:
                yield warn(it.where, it.status_line, f"Status is superseded, but no intent says "
                                                     f"`Supersedes: {it.slug}`")

    def _cycles(self):
        graph = {}  # node -> {node it waits for: (intent, line) of the ref, or None}
        for it in self.intents:
            if it.has_stories:
                graph[it] = dict.fromkeys(it.live)
            for u in it.live:
                graph[u] = {}
                for r in it.depends + u.after:
                    t = self.resolve(it, r.ref)
                    if t is not None:
                        graph[u].setdefault(t, (it, r.line))
        probs, seen, state = [], set(), {}

        def visit(node, stack):
            state[node] = 1
            stack.append(node)
            for nxt in graph.get(node, {}):
                if state.get(nxt) == 1:
                    cycle = stack[stack.index(nxt):] + [nxt]
                    if frozenset(cycle) not in seen:
                        seen.add(frozenset(cycle))
                        names = " → ".join(n.slug for n in cycle)
                        probs.extend(err(i.where, line, f"dependency cycle: {names}")
                                     for a, b in zip(cycle, cycle[1:]) if graph[a][b]
                                     for i, line in [graph[a][b]])
                elif not state.get(nxt):
                    visit(nxt, stack)
            stack.pop()
            state[node] = 2

        for node in list(graph):
            if not state.get(node):
                visit(node, [])
        return probs

    def _layout(self):
        for it in self.intents:
            d = os.path.join(self.repo.root, "intent", it.folder)
            if not os.path.isdir(d):
                continue
            line = it.stories_line if it.has_stories else 1
            stories = {u.slug for u in it.units} if it.has_stories else set()
            if it.has_stories:
                for f in ("spec.md", "plan.md"):
                    if os.path.isfile(os.path.join(d, f)):
                        yield err(it.where, line, f"this intent has stories, so {f} belongs in "
                                                  f"<story-slug>/{f}, not at the top of intent/{it.folder}")
                if len(it.live) > MAX_STORIES:
                    yield warn(it.where, line, f"{len(it.live)} stories; more than {MAX_STORIES} usually "
                                               "means this is two intents")
            for sub in sorted(os.listdir(d)):
                p = os.path.join(d, sub)
                if (os.path.isdir(p) and sub not in stories
                        and any(os.path.isfile(os.path.join(p, f)) for f in ("spec.md", "plan.md"))):
                    yield err(it.where, line, f"intent/{it.folder}/{sub}/ holds a spec or plan, but "
                                              f"{sub!r} isn't a story in the Stories list")

    # ------------------------------------------------------------ stages

    @functools.cached_property
    def hist(self):
        return History(self.repo)

    def state(self, it):
        """The Status that applies: the written one once merged; before that, draft, or superseded
        when another intent folded the draft in."""
        if it.folder in self.repo.base_folders:
            return it.status or "unknown"
        return "superseded" if it.slug in self.successor else "draft"

    def unit_stage(self, u):
        """(stage, since) for a story or a single-story intent."""
        it = u.intent
        if u.dropped:
            return "dropped", ""
        st = self.state(it)
        if it.folder not in self.repo.base_folders:
            ref = self.branch.get(it.folder)
            return st, added_on(self.repo.root, ref, it.path) if st == "draft" and ref else ""
        h = self.hist
        if st != "accepted":
            return st, h.added.get(it.path, "")
        for stage, dates in (("shipped", h.shipped), ("building", h.started)):
            if u.slug in dates:
                return stage, dates[u.slug]
        spec_dir = f"intent/{it.folder}" + (f"/{u.slug}" if u.sid else "")
        for stage, f in (("planned", "plan.md"), ("specced", "spec.md")):
            if f"{spec_dir}/{f}" in self.repo.base_paths:
                return stage, h.added.get(f"{spec_dir}/{f}", "")
        return "accepted", h.added.get(it.path, "")

    def intent_stage(self, it):
        st = self.state(it)
        if st != "accepted":
            return st
        stages = [self.unit_stage(u)[0] for u in it.live]
        if stages and all(s == "shipped" for s in stages):
            return "shipped"
        return "accepted" if all(s == "accepted" for s in stages) else "in progress"

    def dep_state(self, u, r):
        """(met, name, what it needs, what it is) for one dependency of a unit."""
        if r.ref.startswith("#"):
            return pr_state(self.repo.root, r.ref)
        t = self.resolve(u.intent, r.ref)
        if t is None:
            return False, r.ref, "to ship", "reserved"
        if isinstance(t, Intent):
            st = self.intent_stage(t)
            return st == "shipped", r.ref, "to ship", st
        st, same = self.unit_stage(t)[0], t.intent is u.intent
        name = t.sid if same and t.sid else t.slug
        if same and not r.ships:
            return st in SPEC_OR_LATER, name, "its spec merged", st
        return st == "shipped", name, "to ship", st

    def deps_of(self, u):
        return [self.dep_state(u, r) for r in u.intent.depends + u.after]

    def reserved(self, only=None):
        """slug -> where it's promised or named, and which units wait on it, for slugs nothing defines.
        With only, just those promised or named in that intent folder."""
        out = {}

        def entry(slug):
            return out.setdefault(slug, {"promised": [], "named": [], "waiting": []})

        for slug, places in self.promises.items():
            for path, line in places if slug not in self.nodes else ():
                if only in (None, folder_of(path)):
                    entry(slug)["promised"].append(f"{self.where(path)}:{line}")
        for it in self.intents:
            for u in it.live if only in (None, it.folder) else ():
                for r in it.depends + u.after:
                    if self.names_nothing(it, r):
                        e, place = entry(r.ref), f"{it.where}:{r.line}"
                        e["named"] += [place] if place not in e["named"] else []
                        e["waiting"] += [u.slug] if u.slug not in e["waiting"] else []
        return out


def owner(n):
    """(where, line, description) for a node that owns a slug."""
    if isinstance(n, Unit) and n.sid:
        return n.intent.where, n.line, f"story {n.sid} of {n.intent.where}"
    it = n if isinstance(n, Intent) else n.intent
    return it.where, 1, it.where


def prose_warnings(where, text, ranges=None):
    """Warnings for prose that promises later work with no follow-up marker. With ranges, only list
    items and paragraphs that overlap those (1-based, inclusive) line ranges are looked at."""
    lines = scan_lines(text)
    blocks, start = [], None
    for n, line in enumerate(lines + [""], 1):
        if start is not None and (not line.strip() or ITEM.match(line) or line.startswith("#")):
            blocks.append((start, n - 1))
            start = None
        if line.strip() and start is None:
            start = n
    probs = []
    for s, e in blocks:
        if ranges is not None and not any(s <= hi and lo <= e for lo, hi in ranges):
            continue
        if any(MARKER.search(x) for x in lines[s - 1:e]):
            continue
        for n in range(s, e + 1):
            m = PROSE.search(lines[n - 1])
            if m:
                probs.append(warn(where, n, f"{m.group(0)!r} promises later work, and this item has no "
                                            "`→ follow-up: <slug>` marker. With a marker the slug is "
                                            "reserved and `intents status` lists it until someone writes "
                                            "it. Work nobody will do needs no marker."))
    return probs


def changed_ranges(text, fragments):
    """Line ranges where each fragment sits in text. None means the whole file."""
    if fragments is None:
        return None
    ranges = []
    for frag in filter(str.strip, fragments):
        i = text.find(frag)
        if i < 0:
            return None
        s = text.count("\n", 0, i) + 1
        ranges.append((s, s + frag.count("\n")))
    return ranges


# ---------------------------------------------------------------- export

BANNER = ("> Generated by sdlc-kit from [{name}]({url}), which is the source. An edit made here is proposed "
          "back to it as an amendment, then replaced by the merged wording.")
PLAN_STEP = re.compile(r"^ {0,3}(\d+)[.)]\s+\*\*(.+?)\*\*")


def link(repo, rev, path):
    return f"{repo.web}/blob/{rev}/{path}" if repo.web else path


def sections(text):
    """{lowercased `## ` heading without its number: body} for a markdown file."""
    out, name = {}, None
    for line in text.split("\n"):
        h = re.match(r"^##\s+(?:\d+[.)]\s*)?(.+?)\s*$", line)
        if h:
            name = h.group(1).lower()
            out[name] = []
        elif name:
            out[name].append(line)
    return {k: "\n".join(v).strip() for k, v in out.items()}


def acceptance_table(text):
    """The Given / When / Then table under a spec's Acceptance criteria heading, or None."""
    lines, start = text.split("\n"), None
    for n, line in enumerate(lines):
        if start is None and re.match(r"^#+\s+(?:\d+[.)]\s*)?acceptance criteria", line, re.I):
            start = n + 1
        elif start is not None and line.startswith("|"):
            rows = [line]
            for more in lines[n + 1:]:
                if not more.startswith("|"):
                    break
                rows.append(more)
            return "\n".join(rows)
        elif start is not None and line.startswith("#"):
            return None
    return None


def plan_steps(text):
    """[{"n", "title"}] for the numbered steps under a plan's Order of work heading."""
    steps, inside = [], False
    for line in text.split("\n"):
        if line.startswith("## "):
            inside = "order of work" in line.lower()
        elif inside:
            m = PLAN_STEP.match(line)
            if m:
                steps.append({"n": int(m.group(1)), "title": m.group(2).strip().rstrip(".")})
    return steps


def story_block(text, u):
    """(title, body) of a story in intent.md, read from the raw text so code and links survive."""
    lines = text.split("\n")
    first = lines[u.line - 1]
    if first.startswith("###"):
        title = re.sub(r"^###\s+(?:~~)?S\d+\s+[^\s:*~]+:?\s*", "", first).replace("~~", "").strip()
        title = title.split(" (Dropped")[0].strip() or u.slug
        body = []
        for line in lines[u.line:]:
            if line.startswith("## ") or line.startswith("### "):
                break
            body.append(line)
        return title, "\n".join(body).strip()
    rest = plain(STORY.match(first).group("rest")).lstrip(": ").strip()
    for line in lines[u.line:]:
        if not (line.strip() and line[:1].isspace()):
            break
        rest += " " + line.strip()
    return rest.split(".")[0].strip() or u.slug, rest


def digest(text):
    return hashlib.sha256(text.encode()).hexdigest()[:12]


def export_intent(model, it, rev):
    repo, text = model.repo, model.texts[it.path]
    secs = sections(text)
    t = re.search(r"^#\s+(?:Intent:\s*)?(.+)$", text, re.M)
    title = t.group(1).strip() if t else it.slug
    intent_url = link(repo, rev, it.path)
    banner = BANNER.format(name=it.path, url=intent_url)
    outcome = "\n\n".join(f"**{h}**\n\n{secs[k]}" for h, k in (("Problem", "problem"),
                                                                ("Desired outcome", "desired outcome"))
                          if secs.get(k))
    stories = []
    for u in it.units:
        stage, _ = model.unit_stage(u)
        if u.sid:
            name, body = story_block(text, u)
            summary = f"{u.sid} {name}"
        else:
            name, body, summary = title, outcome, title
        folder = f"intent/{it.folder}" + (f"/{u.slug}" if u.sid else "")
        spec_path, plan_path = f"{folder}/spec.md", f"{folder}/plan.md"
        spec = plan = None
        got = repo.blobs(rev, [p for p in (spec_path, plan_path) if p in repo.base_paths])
        parts = [banner, body]
        if spec_path in got:
            table = acceptance_table(got[spec_path])
            spec = {"path": spec_path, "url": link(repo, rev, spec_path), "acceptance": table}
            parts.append(f"**Spec:** [{spec_path}]({spec['url']})"
                         + (f"\n\n**Acceptance tests**\n\n{table}" if table else ""))
        if plan_path in got:
            plan = {"path": plan_path, "url": link(repo, rev, plan_path), "steps": plan_steps(got[plan_path])}
        description = "\n\n".join(p for p in parts if p)
        blocked_by = []
        for r in it.depends + u.after:
            target = model.resolve(it, r.ref)
            slug = r.ref if target is None else target.slug
            blocked_by.append({"ref": r.ref, "slug": slug, "ships": r.ships or not
                               (target is not None and isinstance(target, Unit) and target.intent is it)})
        stories.append({"sid": u.sid, "slug": u.slug, "label": f"sdlc:{u.slug}", "title": name,
                        "summary": summary, "dropped": u.dropped, "stage": stage,
                        "description": description, "digest": digest(description),
                        "blocked_by": blocked_by, "spec": spec, "plan": plan})
    epic = None
    if it.has_stories:
        listing = "\n".join(f"- {s['summary']}" + (" (dropped)" if s["dropped"] else "") for s in stories)
        description = "\n\n".join(p for p in (banner, outcome, f"**Stories**\n\n{listing}") if p)
        epic = {"slug": it.slug, "label": f"sdlc:{it.slug}", "summary": title,
                "description": description, "digest": digest(description)}
    return {"slug": it.slug, "folder": it.folder, "path": it.path, "url": intent_url, "title": title,
            "status": model.state(it), "stage": model.intent_stage(it), "epic": epic, "stories": stories}


# ---------------------------------------------------------------- commands

def cmd_status(model, only):
    intents = sorted(model.intents, key=lambda i: i.folder)
    folder = None
    if only:
        it, _ = model.node(only)
        if it is None:
            print(f"no intent or story named {only!r}", file=sys.stderr)
            return 2
        intents, folder = [it], it.folder

    def detail(it, stage, since, deps):
        parts = []
        if stage == "superseded" and it.slug in model.successor:
            parts.append(f"by {model.successor[it.slug]}")
            if it.folder in model.branch:
                parts.append(f"and its branch {short(model.branch[it.folder])} still exists")
        parts += [model.place(it) if stage == "draft" else "", f"since {since}" if since else "",
                  f"revisit {it.revisit}" if stage == "deferred" and it.revisit else ""]
        unmet = [f"{name} (needs {need}, is {have})" for ok, name, need, have in deps if not ok]
        parts.append("waiting on " + ", ".join(unmet) if unmet else "")
        return ", ".join(p for p in parts if p)

    rows = []
    for it in intents:
        if it.has_stories:
            st = model.intent_stage(it)
            shipped = sum(model.unit_stage(u)[0] == "shipped" for u in it.live) if st == "in progress" else 0
            info = f"{shipped} of {len(it.live)} stories shipped" if st == "in progress" else ""
            rows.append((it.folder, st, model.place(it) if st == "draft" else info))
        for u in it.units:
            stage, since = model.unit_stage(u)
            deps = model.deps_of(u) if stage not in ("shipped", "dropped", "rejected", "superseded") else ()
            rows.append((f"  {u.sid} {u.slug}" if u.sid else it.folder, stage, detail(it, stage, since, deps)))
    print(f"Intents ({model.repo.base}):")
    if not rows:
        print("  none")
    w = max([len(r[0]) for r in rows] + [10])
    for name, stage, info in rows:
        print(f"  {name:<{w}}  {stage:<11}  {info}".rstrip())
    res = model.reserved(folder)
    if res:
        print("Reserved (named, but no intent or story yet):")
        w = max(len(s) for s in res)
        for slug in sorted(res):
            e = res[slug]
            parts = [f"promised at {p}" for p in e["promised"]] + [f"named at {p}" for p in e["named"]]
            parts += ["waited on by " + ", ".join(e["waiting"])] if e["waiting"] else []
            print(f"  {slug:<{w}}  {'; '.join(parts)}")
    return 0


def cmd_check(model, files):
    probs = sorted({*model.check(), *(p for path in model.local for p in prose_warnings(path, model.texts[path]))})
    if files:
        root = os.path.realpath(model.repo.root)
        rels = {os.path.relpath(os.path.realpath(f), root).replace(os.sep, "/") for f in files}
        probs = [p for p in probs if p.path in rels]
    for p in probs:
        print(p)
    if not probs:
        print("no problems found")
    return 1 if any(p.level == "error" for p in probs) else 0


def cmd_deps(model, slug):
    it, u = model.node(slug)
    if not isinstance(u, Unit):
        if it is None:
            print(f"no intent or story named {slug!r}", file=sys.stderr)
        else:
            print(f"{slug} has stories; name one: {', '.join(f'{x.sid} {x.slug}' for x in it.live)}",
                  file=sys.stderr)
        return 2
    deps = model.deps_of(u)
    label = it.folder if u.sid is None else f"{u.sid} {u.slug} of {it.folder}"
    if not deps:
        print(f"{label}: no dependencies")
        return 0
    print(f"{label}:")
    for ok, name, need, have in deps:
        hint = " (no intent or story yet)" if have == "reserved" else ""
        print(f"  {'met  ' if ok else 'UNMET'}  {name}: needs {need}; it's {have}{hint}")
    return 0 if all(d[0] for d in deps) else 1


def cmd_export(model, slug):
    """Merged intents only: a draft can still change, so nothing outside the repo should copy it."""
    repo = model.repo
    merged = [it for it in sorted(model.intents, key=lambda i: i.folder) if it.folder in repo.base_folders]
    if slug:
        it, _ = model.node(slug)
        if it is None:
            print(f"no intent or story named {slug!r}", file=sys.stderr)
            return 2
        if it not in merged:
            print(f"{it.folder} isn't on {repo.base} yet; only merged intents are exported", file=sys.stderr)
            return 1
        merged = [it]
    commit = (repo.git("rev-parse", repo.base) or "").strip()
    branch = re.sub(r"^[^/]+/", "", repo.base) if repo.base.startswith("origin/") else repo.base
    rev = branch if repo.git("rev-parse", "--verify", "--quiet", f"refs/remotes/origin/{branch}") else commit
    print(json.dumps({"base": repo.base, "commit": commit, "repo_url": repo.web,
                      "intents": [export_intent(model, it, rev) for it in merged]}, indent=2,
                     ensure_ascii=False))
    return 0


def cmd_hook():
    data = json.load(sys.stdin)
    ti = data.get("tool_input") or {}
    path = os.path.realpath(ti.get("file_path") or ".")
    # CLAUDE_PROJECT_DIR stays at the session's first root inside a worktree, so ask git where the
    # file itself lives.
    top = run_git(os.path.dirname(path), "rev-parse", "--show-toplevel")
    if not top:
        return 0
    rel = os.path.relpath(path, os.path.realpath(top.strip())).replace(os.sep, "/")
    if not scannable(rel) or not os.path.isfile(path):
        return 0
    with open(path, encoding="utf-8", errors="replace") as f:
        text = f.read().replace("\r\n", "\n")
    if not folder_of(rel) and not is_policy(text):
        return 0
    tool = data.get("tool_name")
    frags = ([ti.get("new_string") or ""] if tool == "Edit"
             else [e.get("new_string") or "" for e in ti.get("edits") or []] if tool == "MultiEdit" else None)
    model = Model(Repo(top.strip()), "worktree")
    probs = sorted({*(p for p in model.check() if p.path == rel),
                    *prose_warnings(rel, text, changed_ranges(text, frags))})
    if any(p.level == "error" for p in probs):
        print(f"intents check: {rel} has relation or layout errors. The file is written; fix them in "
              "this change:", file=sys.stderr)
        for p in probs:
            print(f"  {p}", file=sys.stderr)
        return 2
    if probs:
        ctx = f"intents check on {rel}:\n" + "\n".join(f"  {p}" for p in probs)
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": ctx}}))
    return 0


def main(argv):
    for stream in (sys.stdout, sys.stderr):  # a Windows code page can't print `→` or Arabic
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8")
    args, base = [], None
    it = iter(argv)
    for a in it:
        if a == "--base":
            base = next(it, None)
        elif a.startswith("--base="):
            base = a.split("=", 1)[1]
        else:
            args.append(a)
    cmd = args[0] if args else "status"
    if cmd in ("-h", "--help", "help"):
        print(__doc__)
        return 0
    if cmd == "hook":
        try:
            return cmd_hook()
        except Exception as e:  # never block work on a bug in the checker; tell the user instead
            print(f"intents hook failed: {e}", file=sys.stderr)
            return 1
    top = run_git(os.getcwd(), "rev-parse", "--show-toplevel")
    if not top:
        print("intents: not inside a git repository", file=sys.stderr)
        return 2
    repo = Repo(top.strip(), base)
    if not repo.git("rev-parse", "--verify", "--quiet", repo.base + "^{commit}"):
        print(f"intents: the default branch {repo.base!r} isn't a commit here. Fix --base or "
              "$INTENTS_BASE, or run `git fetch` if it's a remote branch.", file=sys.stderr)
        return 2
    if cmd == "status" and len(args) <= 2:
        return cmd_status(Model(repo, "base"), args[1] if len(args) > 1 else None)
    if cmd == "check":
        return cmd_check(Model(repo, "worktree"), args[1:])
    if cmd == "deps" and len(args) == 2:
        return cmd_deps(Model(repo, "base"), normalize(args[1]))
    if cmd == "export" and len(args) <= 2:
        return cmd_export(Model(repo, "base"), normalize(args[1]) if len(args) > 1 else None)
    print("usage: intents status [<slug>] | check [<file>...] | deps <slug> | export [<slug>] | hook  "
          "[--base <ref>]",
          file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
