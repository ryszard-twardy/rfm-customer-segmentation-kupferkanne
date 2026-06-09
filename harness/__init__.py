"""Kupferkanne KPI parity regression harness.

Snapshots the pipeline's canonical KPIs to a versioned baseline and re-verifies
them with zero-drift assertions. A safety net for pipeline changes (such as the
snake_case rename in issue #9) and a standalone testing-rigor artifact.

BigQuery project and dataset are resolved from environment variables at run
time (see config.py). No project or dataset id is hardcoded anywhere in this
package.
"""

__all__ = ["compare", "compute", "config", "kpi_queries"]
