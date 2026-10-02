"""Tests for `baseline` diff and accept modes (fake query layer, no BigQuery)."""

from __future__ import annotations

import json
from types import SimpleNamespace

import pytest

from harness import cli
from harness.compare import derive_metrics
from harness.compute import render_sql
from harness.config import DATASET_ENV, PROJECT_ENV
from harness.kpi_queries import KPI_DEFS

FAKE_PROJECT = "fake-project"
FAKE_DATASET = "fake_dataset"
FAKE_HEAD = "0" * 40
STALE_SHA = "f" * 64
REASON = "Synthetic reason for the test."

# Synthetic figures: the tests check the accept path, not the warehouse's data.
OLD = {
    "total_revenue": 1000.00,
    "total_profit": 600.00,
    "distinct_customers": 40,
    "distinct_orders": 80,
    "grain_parity": 0,
}
NEW = {**OLD, "total_revenue": 990.50, "total_profit": 590.50}


class FakeBigQuery:
    """Stands in for bigquery.Client: answers each KPI query with a canned value.

    Keyed by the SQL the harness renders from KPI_DEFS, so any query that does
    not come from that single source raises KeyError.
    """

    def __init__(self) -> None:
        self.values = NEW
        self.queries: list = []
        self._name_by_sql = {
            render_sql(kpi, FAKE_PROJECT, FAKE_DATASET): kpi.name for kpi in KPI_DEFS
        }

    def make_client(self, project: str):
        assert project == FAKE_PROJECT
        return self

    def query(self, sql: str):
        self.queries.append(sql)
        rows = [{"value": self.values[self._name_by_sql[sql]]}]
        return SimpleNamespace(result=lambda: rows)


@pytest.fixture
def env(tmp_path, monkeypatch):
    monkeypatch.setenv(PROJECT_ENV, FAKE_PROJECT)
    monkeypatch.setenv(DATASET_ENV, FAKE_DATASET)
    monkeypatch.setattr(cli, "BASELINE_DIR", tmp_path)
    monkeypatch.setattr(cli, "_git_state", lambda: (FAKE_HEAD, False))
    bq = FakeBigQuery()
    monkeypatch.setattr(cli, "_make_client", bq.make_client)
    payload = cli._baseline_payload(OLD, derive_metrics(OLD))
    payload["captured_at_utc"] = "2000-01-01T00:00:00Z"
    baseline = tmp_path / cli.BASELINE_NAME
    _write_committed_format(baseline, payload)
    return SimpleNamespace(
        bq=bq, dir=tmp_path, baseline=baseline, log=tmp_path / cli.ACCEPT_LOG_NAME
    )


def _write_committed_format(path, payload) -> None:
    # The committed baseline's format, independent of cli._dump_json.
    text = json.dumps(payload, indent=2, sort_keys=True) + "\n"
    path.write_text(text, encoding="utf-8", newline="\n")


def _current_queries() -> dict:
    return {k.name: {"sha256": k.query_sha, "sources": list(k.sources)} for k in KPI_DEFS}


def _snapshot(directory) -> dict:
    return {p.name: p.read_bytes() for p in sorted(directory.iterdir())}


@pytest.mark.parametrize(
    "argv",
    [
        ["baseline", "--accept", "--reason", ""],
        ["baseline", "--accept", "--reason", "   "],
        ["baseline", "--accept"],
        ["baseline", "--reason", REASON],
    ],
    ids=["empty", "whitespace", "no-reason", "reason-without-accept"],
)
def test_bad_reason_is_rejected_and_writes_nothing(env, argv):
    before = _snapshot(env.dir)
    assert cli.main(argv) != 0
    assert _snapshot(env.dir) == before
    assert env.bq.queries == []  # rejected before any query runs


def test_accept_writes_new_values_and_one_log_line(env):
    before = env.baseline.read_text(encoding="utf-8")
    assert cli.main(["baseline", "--accept", "--reason", REASON]) == 0

    # Rewritten in place: no new baseline file, no temp file left behind.
    assert sorted(p.name for p in env.dir.iterdir()) == sorted(
        [cli.BASELINE_NAME, cli.ACCEPT_LOG_NAME]
    )
    raw = env.baseline.read_bytes()
    assert b"\r" not in raw and raw.endswith(b"\n")
    payload = json.loads(raw)
    assert payload["primitives"] == NEW
    assert payload["derived"] == derive_metrics(NEW)

    # Same key order and formatting: only the moved lines differ.
    before_lines = before.splitlines()
    after_lines = raw.decode("utf-8").splitlines()
    assert len(after_lines) == len(before_lines)
    moved = {
        old.split(":")[0].strip().strip('"')
        for old, new in zip(before_lines, after_lines)
        if old != new
    }
    assert moved == {
        "captured_at_utc", "aov", "margin_pct", "total_profit", "total_revenue"
    }

    lines = env.log.read_text(encoding="utf-8").splitlines()
    assert len(lines) == 1
    entry = json.loads(lines[0])
    assert entry["reason"] == REASON
    assert entry["git_head"] == FAKE_HEAD
    assert entry["git_dirty"] is False
    assert entry["accepted_at_utc"] == payload["captured_at_utc"]
    assert entry["changes"] == {
        "aov": {"old": 12.5, "new": 12.38},
        "margin_pct": {"old": 60.0, "new": 59.62},
        "total_profit": {"old": 600.0, "new": 590.5},
        "total_revenue": {"old": 1000.0, "new": 990.5},
    }
    assert entry["query_changes"] == {}

    # The accepted baseline is what the comparison now sees.
    assert cli.main(["verify"]) == 0


def test_accept_refreshes_a_stale_query_hash_and_logs_it(env):
    payload = json.loads(env.baseline.read_text(encoding="utf-8"))
    payload["queries"]["total_revenue"]["sha256"] = STALE_SHA
    _write_committed_format(env.baseline, payload)
    env.bq.values = OLD  # no value moves: only the stored hash is out of date

    assert cli.main(["baseline", "--accept", "--reason", REASON]) == 0

    payload = json.loads(env.baseline.read_text(encoding="utf-8"))
    assert payload["primitives"] == OLD
    # Every metadata field describes the accepted values.
    assert payload["queries"] == _current_queries()
    assert payload["captured_at_utc"] != "2000-01-01T00:00:00Z"
    lines = env.log.read_text(encoding="utf-8").splitlines()
    assert len(lines) == 1
    entry = json.loads(lines[0])
    assert entry["accepted_at_utc"] == payload["captured_at_utc"]
    assert entry["changes"] == {}
    assert entry["query_changes"] == {
        "total_revenue": {
            "old": STALE_SHA,
            "new": _current_queries()["total_revenue"]["sha256"],
        }
    }


def test_accept_with_no_changes_writes_nothing(env, capsys):
    env.bq.values = OLD
    before = _snapshot(env.dir)
    assert cli.main(["baseline", "--accept", "--reason", REASON]) == 0
    assert _snapshot(env.dir) == before
    assert "No changes" in capsys.readouterr().out


def test_diff_mode_prints_the_diff_and_writes_nothing(env, capsys):
    before = _snapshot(env.dir)
    assert cli.main(["baseline"]) == 0
    assert _snapshot(env.dir) == before
    out = capsys.readouterr().out
    assert "  total_revenue: 1000.0 -> 990.5" in out
    assert "  margin_pct: 60.0 -> 59.62" in out
    assert "4 changed, 3 unchanged." in out
