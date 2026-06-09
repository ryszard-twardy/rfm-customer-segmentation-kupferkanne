"""CLI for the KPI parity harness.

Two modes:
  baseline  compute KPIs, self-validate against known production values, and
            write baselines/kpi_baseline_<YYYY-MM-DD>.json
  verify    recompute KPIs, diff the latest baseline, exit non-zero on drift
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
from decimal import ROUND_HALF_UP, Decimal
from pathlib import Path

from .compare import compare_kpis, derive_metrics
from .compute import run_primitives
from .config import DATASET_ENV, PROJECT_ENV, ConfigError, resolve_bq_config
from .kpi_queries import EXPECTED_DERIVED, EXPECTED_PRIMITIVES, KPI_DEFS

BASELINE_DIR = Path(__file__).resolve().parent / "baselines"
SCHEMA_VERSION = 1
_COUNT_KPIS = ("distinct_customers", "distinct_orders", "grain_parity")


def _make_client(project: str):
    # Imported lazily so the scaffold and unit tests need no BigQuery creds.
    from google.cloud import bigquery

    return bigquery.Client(project=project)


def _cents(value) -> int:
    return int(Decimal(str(value)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP) * 100)


def _capture(project: str, dataset: str) -> tuple[dict, dict]:
    client = _make_client(project)
    primitives = run_primitives(client, project, dataset)
    derived = derive_metrics(primitives)
    return primitives, derived


def _self_validate(primitives: dict, derived: dict) -> list:
    """Return a list of mismatch messages vs known production values (empty=pass)."""
    problems = []
    for name, expected in EXPECTED_PRIMITIVES.items():
        got = primitives.get(name)
        if name in _COUNT_KPIS:
            ok = got is not None and int(got) == int(expected)
        else:
            ok = got is not None and _cents(got) == _cents(expected)
        if not ok:
            problems.append(f"{name}: captured {got} != expected {expected}")
    for name, expected in EXPECTED_DERIVED.items():
        got = derived.get(name)
        if got is None or _cents(got) != _cents(expected):
            problems.append(f"{name}: derived {got} != expected {expected}")
    return problems


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


def _latest_baseline() -> Path | None:
    if not BASELINE_DIR.exists():
        return None
    files = sorted(BASELINE_DIR.glob("kpi_baseline_*.json"))
    return files[-1] if files else None


def cmd_baseline(_args) -> int:
    project, dataset = resolve_bq_config()
    primitives, derived = _capture(project, dataset)
    problems = _self_validate(primitives, derived)
    if problems:
        print("BASELINE REJECTED - captured KPIs do not match known production values:")
        for line in problems:
            print("  - " + line)
        print("Fix the offending query; never edit the expected values.")
        return 2
    BASELINE_DIR.mkdir(parents=True, exist_ok=True)
    today = dt.datetime.now(dt.timezone.utc).date().isoformat()
    out_path = BASELINE_DIR / f"kpi_baseline_{today}.json"
    payload = _baseline_payload(primitives, derived)
    out_path.write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(f"Baseline written: {out_path.name}")
    for name, value in {**primitives, **derived}.items():
        print(f"  {name} = {value}")
    return 0


def cmd_verify(_args) -> int:
    project, dataset = resolve_bq_config()
    baseline_path = _latest_baseline()
    if baseline_path is None:
        print("No baseline found in baselines/. Run `baseline` first.")
        return 2
    baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
    base_flat = {**baseline["primitives"], **baseline["derived"]}
    primitives, derived = _capture(project, dataset)
    cur_flat = {**primitives, **derived}
    report = compare_kpis(base_flat, cur_flat)
    print(f"Verify against {baseline_path.name}")
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
    sub.add_parser("baseline", help="Compute KPIs and write a versioned baseline.")
    sub.add_parser("verify", help="Recompute KPIs and assert zero drift vs latest baseline.")
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
