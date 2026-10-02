"""Unit tests for the pure diff/derivation logic (no BigQuery, mock data only)."""

from __future__ import annotations

import pytest

from harness.compare import ComparisonReport, compare_kpis, derive_metrics

# Synthetic figures: the tests check the rules, not the warehouse's data.
PRIMITIVES = {
    "total_revenue": 100.10,
    "total_profit": 30.00,
    "distinct_customers": 3,
    "distinct_orders": 4,
    "grain_parity": 0,
}


def test_derive_metrics_rounds_half_up_to_the_cent():
    # AOV = 100.10 / 4 = 25.025 -> 25.03 (half-up; half-even would give 25.02).
    # Margin % = 30.00 / 100.10 * 100 = 29.970... -> 29.97.
    derived = derive_metrics(PRIMITIVES)
    assert derived["aov"] == 25.03
    assert derived["margin_pct"] == 29.97


def test_compare_identical_has_no_drift():
    flat = {**PRIMITIVES, **derive_metrics(PRIMITIVES)}
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
    assert compare_kpis({"distinct_orders": 4}, {"distinct_orders": 4}).ok
    assert not compare_kpis({"distinct_orders": 4}, {"distinct_orders": 5}).ok


def test_grain_parity_drift_is_detected():
    assert compare_kpis({"grain_parity": 0}, {"grain_parity": 0}).ok
    assert not compare_kpis({"grain_parity": 0}, {"grain_parity": 1}).ok


def test_missing_key_is_drift():
    report = compare_kpis({"total_profit": 30.00}, {})
    assert not report.ok
    assert report.drifted()[0].name == "total_profit"


def test_derive_rejects_zero_denominators():
    with pytest.raises(ValueError):
        derive_metrics({"total_revenue": 0.0, "total_profit": 0.0, "distinct_orders": 0})
    with pytest.raises(ValueError):
        derive_metrics({"total_revenue": 0.0, "total_profit": 1.0, "distinct_orders": 5})
