"""CLI for the KPI parity harness.

Two modes:
  baseline  recompute KPIs and print the old -> new diff against
            baselines/kpi_baseline.json; writes nothing. With --accept
            --reason "<why>" it rewrites that file and appends one line to
            the accept log.
  verify    recompute KPIs, diff the baseline, exit non-zero on drift
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

from .compare import compare_kpis, derive_metrics
from .compute import run_primitives
from .config import DATASET_ENV, PROJECT_ENV, ConfigError, resolve_bq_config
from .kpi_queries import KPI_DEFS

BASELINE_DIR = Path(__file__).resolve().parent / "baselines"
# One fixed file: accept dates live in the accept log and in git history.
BASELINE_NAME = "kpi_baseline.json"
ACCEPT_LOG_NAME = "accept_log.jsonl"
SCHEMA_VERSION = 1
_REPO_ROOT = Path(__file__).resolve().parent.parent


def _make_client(project: str):
    # Imported lazily so the scaffold and unit tests need no BigQuery creds.
    from google.cloud import bigquery

    return bigquery.Client(project=project)


def _capture(project: str, dataset: str) -> tuple[dict, dict]:
    client = _make_client(project)
    primitives = run_primitives(client, project, dataset)
    derived = derive_metrics(primitives)
    return primitives, derived


def _baseline_payload(primitives: dict, derived: dict) -> dict:
    now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
    return {
        "schema_version": SCHEMA_VERSION,
        "captured_at_utc": now.isoformat().replace("+00:00", "Z"),
        # Record which env vars define the target, never the values themselves.
        "bq_project_env": PROJECT_ENV,
        "bq_dataset_env": DATASET_ENV,
        "primitives": primitives,
        "derived": derived,
        "queries": {
            kpi.name: {"sha256": kpi.query_sha, "sources": list(kpi.sources)}
            for kpi in KPI_DEFS
        },
    }


def _load_baseline() -> dict | None:
    path = BASELINE_DIR / BASELINE_NAME
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else None


def _dump_json(payload: dict) -> str:
    # One serialisation for every baseline write, so a rewrite diffs minimally.
    return json.dumps(payload, indent=2, sort_keys=True) + "\n"


def _write_atomic(path: Path, text: str) -> None:
    """Write via a temp file in the same directory, then os.replace (LF only)."""
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, path)
    except BaseException:
        Path(tmp).unlink(missing_ok=True)
        raise


def _git_state() -> tuple[str, bool | None]:
    """Return (HEAD sha, tracked files modified?), or ("unknown", None) without git."""
    try:
        head = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=_REPO_ROOT, capture_output=True, text=True, check=True,
        ).stdout.strip()
        status = subprocess.run(
            ["git", "status", "--porcelain", "--untracked-files=no"],
            cwd=_REPO_ROOT, capture_output=True, text=True, check=True,
        ).stdout
    except (OSError, subprocess.CalledProcessError):
        return "unknown", None
    return head, bool(status.strip())


def _keep_unchanged(stored: dict | None, section: str, captured: dict, changed: set) -> dict:
    """Changed KPIs take the captured value; the rest keep the stored one, so
    float noise below the comparison precision never rewrites a line."""
    old = stored.get(section, {}) if stored else {}
    return {
        name: value if name in changed else old[name]
        for name, value in captured.items()
    }


def _query_changes(stored: dict | None) -> dict:
    """Old -> new SHA-256 for each KPI query whose stored hash is not current."""
    queries = stored.get("queries", {}) if stored else {}
    old = {name: query.get("sha256") for name, query in queries.items()}
    new = {kpi.name: kpi.query_sha for kpi in KPI_DEFS}
    return {
        name: {"old": old.get(name), "new": new.get(name)}
        for name in sorted(set(old) | set(new))
        if old.get(name) != new.get(name)
    }


def _show(value) -> str:
    return "(none)" if value is None else str(value)


def cmd_baseline(args) -> int:
    reason = (args.reason or "").strip()
    if args.accept and not reason:
        print("Rejected: --accept needs a non-empty --reason. Nothing written.")
        return 2
    if args.reason is not None and not args.accept:
        print("Rejected: --reason is only read with --accept. Nothing written.")
        return 2

    project, dataset = resolve_bq_config()
    stored = _load_baseline()
    base_flat = {**stored["primitives"], **stored["derived"]} if stored else {}
    primitives, derived = _capture(project, dataset)
    report = compare_kpis(base_flat, {**primitives, **derived})
    changed = report.drifted()
    query_changes = _query_changes(stored)

    print(f"Baseline diff against {BASELINE_NAME if stored else '(no baseline yet)'}")
    for delta in changed:
        print(f"  {delta.name}: {_show(delta.baseline)} -> {_show(delta.current)}")
    print(f"{len(changed)} changed, {len(report.deltas) - len(changed)} unchanged.")
    for name, sha in query_changes.items():
        print(f"  {name} query sha256: {_show(sha['old'])[:12]} -> {_show(sha['new'])[:12]}")
    if query_changes:
        print(f"{len(query_changes)} stored query hash(es) not current.")
    if not changed and not query_changes:
        print("No changes; nothing written.")
        return 0
    if not args.accept:
        print('Diff only; nothing written. To write it: baseline --accept --reason "<why>"')
        return 0

    # Read git state before writing, so the dirty flag describes the code that ran.
    head, dirty = _git_state()
    names = {delta.name for delta in changed}
    # Every metadata field is rebuilt: capture time now, hashes from KPI_DEFS.
    payload = _baseline_payload(
        _keep_unchanged(stored, "primitives", primitives, names),
        _keep_unchanged(stored, "derived", derived, names),
    )
    BASELINE_DIR.mkdir(parents=True, exist_ok=True)
    _write_atomic(BASELINE_DIR / BASELINE_NAME, _dump_json(payload))
    entry = {
        "accepted_at_utc": payload["captured_at_utc"],
        "git_head": head,
        "git_dirty": dirty,
        "reason": reason,
        "changes": {d.name: {"old": d.baseline, "new": d.current} for d in changed},
        "query_changes": query_changes,
    }
    with (BASELINE_DIR / ACCEPT_LOG_NAME).open("a", encoding="utf-8", newline="\n") as fh:
        fh.write(json.dumps(entry) + "\n")
    print(f"Baseline written: {BASELINE_NAME}; logged in {ACCEPT_LOG_NAME}")
    return 0


def cmd_verify(_args) -> int:
    project, dataset = resolve_bq_config()
    baseline = _load_baseline()
    if baseline is None:
        print(f"No baseline at baselines/{BASELINE_NAME}. Run `baseline --accept` first.")
        return 2
    base_flat = {**baseline["primitives"], **baseline["derived"]}
    primitives, derived = _capture(project, dataset)
    cur_flat = {**primitives, **derived}
    report = compare_kpis(base_flat, cur_flat)
    print(f"Verify against {BASELINE_NAME}")
    for delta in report.deltas:
        flag = "DRIFT" if delta.drift else "ok"
        print(f"  [{flag}] {delta.name}: baseline={delta.baseline} current={delta.current}")
    if not report.ok:
        print(f"FAIL - {len(report.drifted())} KPI(s) drifted.")
        return 1
    print("PASS - 0 drift.")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="harness",
        description="Kupferkanne KPI parity regression harness (baseline + verify).",
    )
    sub = parser.add_subparsers(dest="mode", required=True)
    base = sub.add_parser(
        "baseline",
        allow_abbrev=False,
        help="Diff live KPIs against the baseline; write only with --accept.",
    )
    base.add_argument(
        "--accept",
        action="store_true",
        help="Rewrite the baseline and append a line to the accept log.",
    )
    base.add_argument(
        "--reason",
        help="Why the figures moved; required with --accept, recorded in the log.",
    )
    sub.add_parser("verify", help="Recompute KPIs and assert zero drift vs the baseline.")
    return parser


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    try:
        if args.mode == "baseline":
            return cmd_baseline(args)
        if args.mode == "verify":
            return cmd_verify(args)
    except ConfigError as exc:
        print(f"Config error: {exc}")
        return 3
    return 64


if __name__ == "__main__":
    sys.exit(main())
