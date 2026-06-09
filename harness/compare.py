"""Pure comparison and derivation logic for the KPI parity harness.

No BigQuery, no I/O: every function here operates on plain dictionaries so the
diff rules can be unit-tested with mock data. Rounding policy is explicit:

  counts / grain : exact integer equality
  currency       : exact to the cent (2 dp, half-up, matching BigQuery ROUND)
  derived ratios : 2 dp, half-up
"""

from __future__ import annotations

from dataclasses import dataclass
from decimal import ROUND_HALF_UP, Decimal

from .kpi_queries import KIND_COUNT, KIND_CURRENCY, KIND_GRAIN, KPI_DEFS

_KIND_BY_NAME = {d.name: d.kind for d in KPI_DEFS}
_CENT = Decimal("0.01")


def _q2(value) -> Decimal:
    """Quantize to two decimals, half-up. Uses str() to avoid float repr drift."""
    return Decimal(str(value)).quantize(_CENT, rounding=ROUND_HALF_UP)


def derive_metrics(primitives: dict) -> dict:
    """Compute derived KPIs from primitives.

    AOV = revenue / orders ; Margin % = profit / revenue * 100. Both 2 dp.
    Raises ValueError on a zero denominator rather than emitting a bogus ratio.
    """
    revenue = Decimal(str(primitives["total_revenue"]))
    profit = Decimal(str(primitives["total_profit"]))
    orders = Decimal(str(primitives["distinct_orders"]))
    if orders == 0:
        raise ValueError("distinct_orders is 0 - cannot compute AOV")
    if revenue == 0:
        raise ValueError("total_revenue is 0 - cannot compute Margin %")
    aov = (revenue / orders).quantize(_CENT, rounding=ROUND_HALF_UP)
    margin_pct = (profit / revenue * Decimal(100)).quantize(
        _CENT, rounding=ROUND_HALF_UP
    )
    return {"aov": float(aov), "margin_pct": float(margin_pct)}


def _values_equal(kind: str, a, b) -> bool:
    if kind in (KIND_COUNT, KIND_GRAIN):
        return int(a) == int(b)
    # currency and derived ratios both compare at the cent.
    return _q2(a) == _q2(b)


@dataclass(frozen=True)
class KpiDelta:
    """The baseline vs current outcome for a single KPI."""

    name: str
    baseline: object
    current: object
    drift: bool


@dataclass(frozen=True)
class ComparisonReport:
    """Full comparison result across all KPIs."""

    deltas: tuple
    ok: bool

    def drifted(self) -> tuple:
        return tuple(d for d in self.deltas if d.drift)


def compare_kpis(baseline: dict, current: dict) -> ComparisonReport:
    """Compare two flat {name: value} maps (primitives + derived merged).

    A missing key on either side, or a kind-aware value mismatch, is drift.
    Unknown names (for example derived ratios) compare at the cent.
    """
    names = sorted(set(baseline) | set(current))
    deltas = []
    for name in names:
        kind = _KIND_BY_NAME.get(name, KIND_CURRENCY)
        base_value = baseline.get(name)
        cur_value = current.get(name)
        if base_value is None or cur_value is None:
            drift = True
        else:
            drift = not _values_equal(kind, base_value, cur_value)
        deltas.append(
            KpiDelta(name=name, baseline=base_value, current=cur_value, drift=drift)
        )
    ok = not any(d.drift for d in deltas)
    return ComparisonReport(deltas=tuple(deltas), ok=ok)
