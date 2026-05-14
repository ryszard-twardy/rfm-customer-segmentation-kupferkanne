"""
SQL blank-line analyzer and applier for Phase F (Perfection Loop).

Refined conventions (derived from existing file structure):

Canonical positions where exactly ONE blank line is required ABOVE:
  1. CREATE OR REPLACE VIEW <name>
  2. CREATE OR REPLACE TABLE <name>
  3. DROP TABLE IF EXISTS <name>
  4. Top-level WITH clause:  ^WITH\b (NOT when it's the body of CREATE ... AS)
  5. Sibling CTEs:  blank above the second CTE-name line after a `),` line
  6. Main SELECT after last CTE: blank above the top-level SELECT after closing `)`

Special handling (attached blocks, no blank between):
  - DROP TABLE IF EXISTS immediately above CREATE OR REPLACE TABLE → paired,
    they are glued. The DROP gets the blank-above; CREATE does not.
  - WITH immediately below `CREATE ... AS` (any line ending in `AS`) → glued.
  - CREATE/DROP with leading inline comments (`-- ...`) attached above (no blank
    gap) → the comment block is part of the statement; blank goes ABOVE the
    topmost comment line, not between comment and CREATE.

Anti-patterns (NOT touched):
  - UNION ALL: no insertion. Existing codebase convention has no blanks above
    UNION ALL in audit/validation chains (all are compact single-line SELECTs
    inside `expected AS (...)` / `audit AS (...)` CTEs).
  - DECLARE at start of script: first statement after header, may have blank
    above if separated by a blank, but never required.

Cleanup actions (always applied):
  - Collapse 2+ consecutive blank lines anywhere → 1 blank line.
  - Strip trailing blank lines, guarantee exactly one trailing newline.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


CREATE_VIEW = re.compile(r"^\s*CREATE\s+OR\s+REPLACE\s+VIEW\b", re.IGNORECASE)
CREATE_TABLE = re.compile(r"^\s*CREATE\s+OR\s+REPLACE\s+TABLE\b", re.IGNORECASE)
DROP_TABLE = re.compile(r"^\s*DROP\s+TABLE\s+IF\s+EXISTS\b", re.IGNORECASE)
WITH_ANY = re.compile(r"^\s*WITH\b", re.IGNORECASE)
WITH_NAME_AS = re.compile(r"^\s*WITH\s+\w+\s+AS\s*\(", re.IGNORECASE)
COMMENT_LINE = re.compile(r"^\s*--")
TOP_SELECT = re.compile(r"^SELECT\b", re.IGNORECASE)
CTE_CLOSE_COMMA = re.compile(r"^\s*\)\s*,\s*(--.*)?$")
CTE_NAME_AS_PAREN = re.compile(r"^\s*\w+\s+AS\s*\(\s*(--.*)?$", re.IGNORECASE)
CTE_LAST_CLOSE = re.compile(r"^\)\s*(--.*)?$")  # exactly ")" at column 0


def is_blank(line: str) -> bool:
    return line.strip() == ""


def strip_inline_comment(s: str) -> str:
    """Remove trailing `-- comment`, preserve content before it."""
    # Naive: handle the `--` outside of any string. Good enough for these files.
    idx = s.find("--")
    if idx == -1:
        return s
    return s[:idx].rstrip()


def block_top(lines: list[str], idx: int) -> int:
    """Return the topmost line index of the contiguous comment block directly
    attached above `idx` (no blank lines between). If line `idx-1` is not a
    comment, return `idx` itself."""
    top = idx
    while top > 0 and COMMENT_LINE.match(lines[top - 1]):
        top -= 1
    return top


def needs_blank_above_block(lines: list[str], idx: int) -> int | None:
    """If the block starting at `idx` (including attached comment header above)
    lacks a blank line above its topmost line, return the row index where a
    blank should be inserted. Otherwise return None."""
    top = block_top(lines, idx)
    if top == 0:
        return None  # first line of file
    if is_blank(lines[top - 1]):
        return None
    return top


def prev_non_blank_idx(lines: list[str], idx: int) -> int | None:
    j = idx - 1
    while j >= 0 and is_blank(lines[j]):
        j -= 1
    return j if j >= 0 else None


EXECUTE_IMMEDIATE_OPEN = re.compile(r"\bEXECUTE\s+IMMEDIATE\s+FORMAT\s*\(", re.IGNORECASE)


def compute_skip_mask(lines: list[str]) -> list[bool]:
    """Return a per-line mask. True = inside an `EXECUTE IMMEDIATE FORMAT( ... )`
    dynamic-SQL block (the SQL there is a string template the author wrote
    deliberately; we don't touch its whitespace). The opening line that contains
    `EXECUTE IMMEDIATE FORMAT(` is the start; we count balanced parentheses
    OUTSIDE of string literals (rough: ignore `(`/`)` between matching pairs of
    `'''`). Lines from after the opening `(` up to the matching `)` line are
    marked True. The boundary lines themselves are also marked True for safety
    so we don't insert blanks right next to them.
    """
    n = len(lines)
    mask = [False] * n
    i = 0
    while i < n:
        if EXECUTE_IMMEDIATE_OPEN.search(lines[i]):
            # Find matching `)` at depth 0, scanning forward.
            # Strip triple-quoted regions before counting parens.
            depth = 0
            start = i
            j = i
            # First, find where the `(` of FORMAT(  appears and start depth=1
            # right after it. We count from the line `i` onward.
            in_tq = False
            tq = None
            # Process character-by-character across remaining text.
            for j in range(i, n):
                ln = lines[j]
                k = 0
                while k < len(ln):
                    if not in_tq:
                        if ln.startswith("'''", k):
                            in_tq = True
                            tq = "'''"
                            k += 3
                            continue
                        if ln.startswith('"""', k):
                            in_tq = True
                            tq = '"""'
                            k += 3
                            continue
                        ch = ln[k]
                        if ch == "(":
                            depth += 1
                        elif ch == ")":
                            depth -= 1
                            if depth == 0 and j > i:
                                # closed
                                for m in range(start, j + 1):
                                    mask[m] = True
                                # Continue outer loop after j
                                i = j + 1
                                break
                        k += 1
                    else:
                        if ln.startswith(tq, k):
                            in_tq = False
                            tq = None
                            k += 3
                            continue
                        k += 1
                else:
                    # finished line without breaking; continue to next line
                    continue
                # broke out of inner while because depth==0
                break
            else:
                # never closed (malformed); mark all remaining and exit
                for m in range(start, n):
                    mask[m] = True
                i = n
            # Advance past the closing
        else:
            i += 1
    return mask


def analyze(text: str) -> dict:
    lines = text.splitlines()
    n = len(lines)
    string_mask = compute_skip_mask(lines)
    missing: list[tuple[int, str, str]] = []
    insert_positions: set[int] = set()

    for i, ln in enumerate(lines):
        if string_mask[i]:
            continue  # don't touch SQL embedded inside string literals
        s = ln.rstrip()

        # CREATE OR REPLACE TABLE / VIEW
        if CREATE_TABLE.match(s) or CREATE_VIEW.match(s):
            # Special: glued to DROP TABLE IF EXISTS immediately above
            pj = prev_non_blank_idx(lines, i)
            if pj is not None and DROP_TABLE.match(lines[pj].rstrip()):
                # paired; check that there's no blank between DROP and CREATE
                # (they should be glued). If a blank exists, that's a separate
                # cleanup we DON'T do (we never remove user-intended blanks
                # between DROP/CREATE pairs). Skip insertion.
                continue
            pos = needs_blank_above_block(lines, i)
            if pos is not None:
                if pos not in insert_positions:
                    insert_positions.add(pos)
                    missing.append((pos, "blank_above_create", s[:70]))
            continue

        # DROP TABLE IF EXISTS
        if DROP_TABLE.match(s):
            pos = needs_blank_above_block(lines, i)
            if pos is not None:
                if pos not in insert_positions:
                    insert_positions.add(pos)
                    missing.append((pos, "blank_above_drop", s[:70]))
            continue

        # Top-level WITH
        if WITH_ANY.match(s):
            # Skip if WITH is body of CREATE...AS (previous non-blank ends with AS)
            pj = prev_non_blank_idx(lines, i)
            if pj is not None:
                prev_clean = strip_inline_comment(lines[pj]).rstrip()
                if re.search(r"\bAS\s*$", prev_clean, re.IGNORECASE):
                    continue  # body of CREATE ... AS
                if prev_clean.endswith("("):
                    continue  # body of `SET x = (` or similar subquery
            pos = needs_blank_above_block(lines, i)
            if pos is not None:
                if pos not in insert_positions:
                    insert_positions.add(pos)
                    missing.append((pos, "blank_above_with", s[:70]))
            continue

        # Sibling CTE: line is `),` and next non-blank is `<name> AS (`
        if CTE_CLOSE_COMMA.match(s):
            j = i + 1
            while j < n and is_blank(lines[j]):
                j += 1
            if j < n and CTE_NAME_AS_PAREN.match(lines[j].rstrip()):
                if not is_blank(lines[j - 1]):
                    if j not in insert_positions:
                        insert_positions.add(j)
                        missing.append((j, "blank_between_ctes", lines[j].rstrip()[:70]))
            continue

        # Main SELECT after last CTE: `)` alone at top level, then SELECT at col 0
        if CTE_LAST_CLOSE.match(ln):  # match full line (preserves indent check)
            # Confirm this `)` is at column 0 (top-level)
            if not ln.startswith(")"):
                continue
            j = i + 1
            while j < n and is_blank(lines[j]):
                j += 1
            if j < n and TOP_SELECT.match(lines[j].rstrip()):
                if not is_blank(lines[j - 1]):
                    if j not in insert_positions:
                        insert_positions.add(j)
                        missing.append((j, "blank_before_main_select", lines[j].rstrip()[:70]))
            continue

    # Duplicate blank line ranges
    dup_blank_ranges = []
    i = 0
    while i < n:
        if is_blank(lines[i]):
            j = i
            while j < n and is_blank(lines[j]):
                j += 1
            if j - i > 1:
                dup_blank_ranges.append((i, j))
            i = j
        else:
            i += 1

    # Trailing blanks at EOF
    trailing_blanks = 0
    k = n - 1
    while k >= 0 and is_blank(lines[k]):
        trailing_blanks += 1
        k -= 1

    return {
        "lines": lines,
        "n": n,
        "missing_blanks": missing,
        "dup_blank_ranges": dup_blank_ranges,
        "trailing_blanks": trailing_blanks,
    }


def apply_fixes(text: str, rep: dict) -> tuple[str, dict]:
    lines = list(rep["lines"])
    positions_to_insert = sorted(
        {idx for idx, _kind, _desc in rep["missing_blanks"]}, reverse=True
    )
    inserted = 0
    for idx in positions_to_insert:
        if idx > 0 and not is_blank(lines[idx - 1]):
            lines.insert(idx, "")
            inserted += 1

    # Collapse 2+ consecutive blanks → 1
    out: list[str] = []
    blank_run = 0
    collapsed = 0
    for ln in lines:
        if is_blank(ln):
            blank_run += 1
            if blank_run == 1:
                out.append("")
            else:
                collapsed += 1
        else:
            blank_run = 0
            out.append(ln)

    # Strip trailing blank lines
    stripped_trailing = 0
    while out and is_blank(out[-1]):
        out.pop()
        stripped_trailing += 1

    new_text = "\n".join(out) + "\n"
    return new_text, {
        "inserted": inserted,
        "collapsed": collapsed,
        "stripped_trailing_blanks": stripped_trailing,
    }


def verify(text: str) -> list[str]:
    rep = analyze(text)
    issues: list[str] = []
    for idx, kind, desc in rep["missing_blanks"]:
        issues.append(f"line {idx+1}: {kind}: {desc}")
    for a, b in rep["dup_blank_ranges"]:
        issues.append(f"lines {a+1}-{b}: duplicate blank lines ({b-a} consecutive)")
    if rep["trailing_blanks"] > 0:
        issues.append(f"trailing blank lines at EOF: {rep['trailing_blanks']}")
    return issues


def process_file(path: Path, dry_run: bool = False) -> dict:
    original = path.read_text(encoding="utf-8")
    rep = analyze(original)
    new_text, stats = apply_fixes(original, rep)
    pass2 = verify(new_text)
    if not dry_run and new_text != original:
        path.write_text(new_text, encoding="utf-8", newline="\n")
    return {
        "path": str(path),
        "pre_missing": len(rep["missing_blanks"]),
        "pre_dup_ranges": len(rep["dup_blank_ranges"]),
        "pre_trailing_blanks": rep["trailing_blanks"],
        "stats": stats,
        "pass2_issues": pass2,
        "changed": new_text != original,
    }


if __name__ == "__main__":
    args = sys.argv[1:]
    dry = "--dry" in args
    verbose = "--verbose" in args
    args = [a for a in args if a not in ("--dry", "--verbose")]
    for arg in args:
        p = Path(arg)
        text = p.read_text(encoding="utf-8")
        rep = analyze(text)
        new_text, stats = apply_fixes(text, rep)
        pass2 = verify(new_text)
        if verbose:
            print(f"=== {p}")
            for idx, kind, desc in rep["missing_blanks"]:
                print(f"  INSERT at L{idx+1}  {kind}  | {desc}")
            for a, b in rep["dup_blank_ranges"]:
                print(f"  COLLAPSE L{a+1}-L{b} ({b-a} consecutive)")
            if rep["trailing_blanks"]:
                print(f"  STRIP {rep['trailing_blanks']} trailing blanks")
            print(f"  stats={stats}  pass2={'PASS' if not pass2 else pass2}")
            print()
        else:
            print({
                "path": str(p),
                "missing": len(rep["missing_blanks"]),
                "dup_ranges": len(rep["dup_blank_ranges"]),
                "trailing": rep["trailing_blanks"],
                "stats": stats,
                "pass2": "PASS" if not pass2 else pass2,
                "changed": new_text != text,
            })
        if not dry and new_text != text:
            p.write_text(new_text, encoding="utf-8", newline="\n")
