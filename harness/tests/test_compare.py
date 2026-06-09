"""Unit tests for the pure diff/derivation logic (no BigQuery, mock data only)."""

from __future__ import annotations

import pytest

from harness.compare import ComparisonReport, compare_kpis, derive_metrics
from harness.kpi_queries import EXPECTED_DERIVED, EXPECTED_PRIMITIVES


def test_derive_metrics_matches_known_production():
    # Independently confirms AOV=50.55 and Margin %=59.78 from the primitives,
    # so EXPECTED_DERIVED can never silently diverge from EXPECTED_PRIMITIVES.
    derived = derive_metrics(EXPECTED_PRIMITIVES)
    assert derived["aov"] == EXPECTED_DERIVED["aov"]
    assert derived["margin_pct"] == EXPECTED_DERIVED["margin_pct"]


def test_compare_identical_has_no_drift():
    flat = {**EXPECTED_PRIMITIVES, **EXPECTED_DERIVED}
    report = compare_kpis(flat, dict(flat))
    assert isinstance(report, ComparisonReport)
    assert report.ok
    assert report.drifted() == ()


def test_currency_compares_to_the_cent():
    base = {"total_revenue": 100.00}
    # Sub-cent noise does not count as drift.
    assert compare_kpis(base, {"total_revenue": 100.004}).ok
    # A one-cent change does.
    assert not compare_kpis(base, {"total_revenue": 100.01}).ok


def test_counts_require_exact_equality():
    assert compare_kpis({"distinct_orders": 168777}, {"distinct_orders": 168777}).ok
    assert not compare_kpis({"distinct_orders": 168777}, {"distinct_orders": 168778}).ok


def test_grain_parity_drift_is_detected():
    assert compare_kpis({"grain_parity": 0}, {"grain_parity": 0}).ok
    assert not compare_kpis({"grain_parity": 0}, {"grain_parity": 1}).ok


def test_missing_key_is_drift():
    report = compare_kpis({"total_profit": 5100089.72}, {})
    assert not report.ok
    assert report.drifted()[0].name == "total_profit"


def test_derive_rejects_zero_denominators():
    with pytest.raises(ValueError):
        derive_metrics({"total_revenue": 0.0, "total_profit": 0.0, "distinct_orders": 0})
    with pytest.raises(ValueError):
        derive_metrics({"total_revenue": 0.0, "total_profit": 1.0, "distinct_orders": 5})
