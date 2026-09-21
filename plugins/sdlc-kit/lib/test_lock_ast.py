#!/usr/bin/env python3
"""Add-only lock checks for Python test files, used by test-lock.sh and test-lock-guard.sh.

A Python test file locked add-only may gain new tests, fixtures, helpers, and imports. But at every
lock point:
  - every top-level statement that existed then must still exist unchanged. Statements are compared
    by AST, so formatting and comments don't matter. That covers tests, fixtures, helpers, constants,
    and decorators;
  - every name imported then must still be imported (import lines may be extended);
  - nothing may be added that weakens existing tests without editing them: a module-level
    `pytestmark`, `collect_ignore`, a module-level skip/xfail/importorskip call, or an autouse fixture.

  test_lock_ast.py check <root> <rel> <commit>...  check the working-tree file; exit 1 on problems
  test_lock_ast.py guard <root> <rel> <commit>...  check the file a PreToolUse Edit/MultiEdit/Write
                                                   (JSON on stdin) would produce; exit 1 on problems
Problems are printed on stdout, one per line.
"""
import ast
import json
import subprocess
import sys
from collections import Counter

WEAKENING_NAMES = {"pytestmark", "collect_ignore", "collect_ignore_glob"}
WEAKENING_CALLS = ("skip", "xfail", "importorskip")


def _is_docstring(index, stmt):
    return (
        index == 0
        and isinstance(stmt, ast.Expr)
        and isinstance(stmt.value, ast.Constant)
        and isinstance(stmt.value.value, str)
    )


def _statements(tree):
    """Top-level statements other than imports and the module docstring, with their AST dumps."""
    return [
        (stmt, ast.dump(stmt))
        for index, stmt in enumerate(tree.body)
        if not isinstance(stmt, (ast.Import, ast.ImportFrom)) and not _is_docstring(index, stmt)
    ]


def _imported_names(tree):
    names = set()
    for stmt in tree.body:
        if isinstance(stmt, ast.Import):
            names |= {("", alias.name, alias.asname) for alias in stmt.names}
        elif isinstance(stmt, ast.ImportFrom):
            module = "." * stmt.level + (stmt.module or "")
            names |= {(module, alias.name, alias.asname) for alias in stmt.names}
    return names


def _label(stmt):
    name = getattr(stmt, "name", None)
    if name:
        return name
    if isinstance(stmt, ast.Assign) and isinstance(stmt.targets[0], ast.Name):
        return stmt.targets[0].id
    return f"{type(stmt).__name__} statement"


def _weakening(stmt):
    targets = []
    if isinstance(stmt, ast.Assign):
        targets = stmt.targets
    elif isinstance(stmt, (ast.AnnAssign, ast.AugAssign)):
        targets = [stmt.target]
    for target in targets:
        if isinstance(target, ast.Name) and target.id in WEAKENING_NAMES:
            return f"adds module-level `{target.id}`, which would affect locked tests"
    if isinstance(stmt, ast.Expr) and isinstance(stmt.value, ast.Call):
        func = ast.unparse(stmt.value.func)
        if func.split(".")[-1] in WEAKENING_CALLS:
            return f"adds a module-level `{func}(...)` call, which would affect locked tests"
    if isinstance(stmt, (ast.FunctionDef, ast.AsyncFunctionDef)):
        for decorator in stmt.decorator_list:
            if isinstance(decorator, ast.Call) and any(
                kw.arg == "autouse" and isinstance(kw.value, ast.Constant) and kw.value.value is True
                for kw in decorator.keywords
            ):
                return f"adds autouse fixture `{stmt.name}`, which would affect locked tests"
    return None


def problems(old_source, new_source):
    if new_source is None:
        return ["the file was deleted"]
    try:
        new_tree = ast.parse(new_source)
    except SyntaxError as error:
        return [f"the file would not parse ({error.msg}, line {error.lineno})"]
    old_tree = ast.parse(old_source)
    found = []

    old_statements, new_statements = _statements(old_tree), _statements(new_tree)
    available = Counter(dump for _, dump in new_statements)
    for stmt, dump in old_statements:
        if available[dump] > 0:
            available[dump] -= 1
        else:
            found.append(f"locked `{_label(stmt)}` was changed or removed")

    for module, name, asname in sorted(_imported_names(old_tree) - _imported_names(new_tree), key=str):
        where = f" from `{module}`" if module else ""
        found.append(f"import of `{name}`{where} was removed")

    existing = Counter(dump for _, dump in old_statements)
    for stmt, dump in new_statements:
        if existing[dump] > 0:
            existing[dump] -= 1
            continue
        weakening = _weakening(stmt)
        if weakening:
            found.append(weakening)
    return found


def _read(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return handle.read()
    except FileNotFoundError:
        return None


def _show(root, commit, rel):
    return subprocess.run(
        ["git", "-C", root, "show", f"{commit}:{rel}"],
        capture_output=True, text=True, check=True,
    ).stdout


def _apply_edits(content, edits):
    for edit in edits:
        old, new = edit.get("old_string"), edit.get("new_string", "")
        if not old or old not in content:
            continue  # the tool itself will reject this edit
        content = content.replace(old, new) if edit.get("replace_all") else content.replace(old, new, 1)
    return content


def _proposed(root, rel):
    data = json.load(sys.stdin)
    tool, tool_input = data.get("tool_name"), data.get("tool_input", {})
    current = _read(f"{root}/{rel}") or ""
    if tool == "Write":
        return tool_input.get("content", "")
    if tool == "Edit":
        return _apply_edits(current, [tool_input])
    if tool == "MultiEdit":
        return _apply_edits(current, tool_input.get("edits", []))
    raise SystemExit(f"{tool} can't be checked on an add-only locked file")


def main(argv):
    if len(argv) < 5 or argv[1] not in ("check", "guard"):
        print(__doc__, file=sys.stderr)
        return 2
    mode, root, rel, commits = argv[1], argv[2], argv[3], argv[4:]
    try:
        new_source = _read(f"{root}/{rel}") if mode == "check" else _proposed(root, rel)
    except SystemExit as error:
        print(error)
        return 1
    seen, report = set(), []
    for commit in commits:
        try:
            old_source = _show(root, commit, rel)
        except subprocess.CalledProcessError:
            report.append(f"lock point {commit[:8]} can't be read from git (missing commit or file)")
            continue
        for problem in problems(old_source, new_source):
            line = f"{problem} (lock point {commit[:8]})"
            if problem not in seen:
                seen.add(problem)
                report.append(line)
    for line in report:
        print(line)
    return 1 if report else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
