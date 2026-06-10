"""Canonical KPI definitions for the Kupferkanne pipeline parity harness.

Every KPI is a single-value query whose SQL is derived from the curated DDL in
sql/ (03_rfm_pipeline -> sales_curated, 04_items_for_bi -> v_items_for_bi).
Project and dataset are injected at run time from environment variables (see
config.py); nothing here hardcodes a BigQuery project or dataset id.

Column provenance (verified against the real DDL):
  sales_curated.order_value   = ROUND(SUM(line_net_amount), 2)              -> revenue
  sales_curated.order_profit  = ROUND(SUM(line_net_amount) - SUM(qty*cost)) -> profit
  sales_curated.customer_id, sales_curated.order_id                          -> identity
  v_items_for_bi.order_id                                                   -> line grain key
"""

from __future__ import annotations

import hashlib
from dataclasses import dataclass

# KPI kinds drive comparison semantics in compare.py.
KIND_COUNT = "count"        # integer, exact equality
KIND_CURRENCY = "currency"  # money amount, exact to the cent
KIND_GRAIN = "grain"        # integer parity counter, must equal 0

SALES_CURATED = "sales_curated"
V_ITEMS_FOR_BI = "v_items_for_bi"


@dataclass(frozen=True)
class KpiDef:
    """One canonical KPI: a name, a kind, a SQL template, and its sources."""

    name: str
    kind: str
    sql_template: str          # uses {sales_curated} / {v_items_for_bi} placeholders
    sources: tuple[str, ...]

    @property
    def query_sha(self) -> str:
        """SHA-256 of the placeholder template.

        Stable across environments (no project/dataset baked in) and changes
        only when the KPI logic changes - which is exactly the regression
        signal a baseline should capture.
        """
        return hashlib.sha256(self.sql_template.encode("utf-8")).hexdigest()


KPI_DEFS: tuple[KpiDef, ...] = (
    KpiDef(
        name="total_revenue",
        kind=KIND_CURRENCY,
        sql_template="SELECT ROUND(SUM(order_value), 2) AS value FROM `{sales_curated}`",
        sources=(SALES_CURATED,),
    ),
    KpiDef(
        name="total_profit",
        kind=KIND_CURRENCY,
        sql_template="SELECT ROUND(SUM(order_profit), 2) AS value FROM `{sales_curated}`",
        sources=(SALES_CURATED,),
    ),
    KpiDef(
        name="distinct_customers",
        kind=KIND_COUNT,
        sql_template="SELECT COUNT(DISTINCT customer_id) AS value FROM `{sales_curated}`",
        sources=(SALES_CURATED,),
    ),
    KpiDef(
        name="distinct_orders",
        kind=KIND_COUNT,
        sql_template="SELECT COUNT(DISTINCT order_id) AS value FROM `{sales_curated}`",
        sources=(SALES_CURATED,),
    ),
    # Grain parity: order-grain order set vs line-grain aggregated to order
    # grain. Counts orders present on exactly one side; must be 0.
    KpiDef(
        name="grain_parity",
        kind=KIND_GRAIN,
        sql_template=(
            "SELECT COUNT(*) AS value FROM (\n"
            "  SELECT o.order_id AS o_order, l.order_id AS l_order\n"
            "  FROM (SELECT order_id FROM `{sales_curated}` GROUP BY order_id) AS o\n"
            "  FULL OUTER JOIN (\n"
            "    SELECT order_id FROM `{v_items_for_bi}` GROUP BY order_id\n"
            "  ) AS l\n"
            "    ON o.order_id = l.order_id\n"
            "  WHERE o.order_id IS NULL OR l.order_id IS NULL\n"
            ")"
        ),
        sources=(SALES_CURATED, V_ITEMS_FOR_BI),
    ),
)

# Known production reference values. These are the harness's own correctness
# test: a freshly captured baseline MUST equal these. If a captured value
# differs, the QUERY is wrong - fix the query, never edit these numbers.
EXPECTED_PRIMITIVES: dict = {
    "total_revenue": 8531365.52,
    "total_profit": 5100089.72,
    "distinct_customers": 14967,
    "distinct_orders": 168777,
    "grain_parity": 0,
}

# Derived values are computed in compare.derive_metrics, not stored as
# primitives. Listed here only so the build-time self-test can confirm the
# derivation lands on the documented figures.
EXPECTED_DERIVED: dict = {
    "aov": 50.55,        # revenue / orders, 2 dp
    "margin_pct": 59.78,  # profit / revenue * 100, 2 dp
}
