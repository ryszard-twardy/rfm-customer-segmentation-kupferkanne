"""Live KPI computation against BigQuery.

Impure: this module touches the network and BigQuery auth. The pure diff and
derivation logic lives in compare.py so it can be unit-tested without creds.
"""

from __future__ import annotations

from .kpi_queries import KIND_COUNT, KIND_GRAIN, KPI_DEFS, KpiDef


def fqn(project: str, dataset: str, obj: str) -> str:
    """Fully qualified `project.dataset.object` reference."""
    return f"{project}.{dataset}.{obj}"


def render_sql(kpi: KpiDef, project: str, dataset: str) -> str:
    """Resolve a KPI template's placeholders to real table references."""
    return kpi.sql_template.format(
        sales_curated=fqn(project, dataset, "sales_curated"),
        v_items_for_bi=fqn(project, dataset, "v_items_for_bi"),
    )


def run_primitives(client, project: str, dataset: str) -> dict:
    """Execute each KPI query and return {name: value}.

    Counts and grain values are coerced to int; currency values to float.
    `client` is any object exposing query(sql).result() (a bigquery.Client).
    """
    out: dict = {}
    for kpi in KPI_DEFS:
        sql = render_sql(kpi, project, dataset)
        rows = list(client.query(sql).result())
        value = rows[0]["value"]
        if kpi.kind in (KIND_COUNT, KIND_GRAIN):
            out[kpi.name] = int(value)
        else:
            out[kpi.name] = float(value)
    return out
