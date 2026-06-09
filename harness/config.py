"""Environment-driven BigQuery configuration.

The project and dataset ids are read from environment variables only, never
hardcoded. This keeps committed code free of environment-specific identifiers
and lets the same harness run against any clone of the warehouse.
"""

from __future__ import annotations

import os

PROJECT_ENV = "KK_BQ_PROJECT"
DATASET_ENV = "KK_BQ_DATASET"


class ConfigError(RuntimeError):
    """Raised when required BigQuery configuration is missing."""


def resolve_bq_config() -> tuple[str, str]:
    """Return (project, dataset) from the environment.

    Raises ConfigError with an actionable message naming the unset variable(s)
    so a missing setting is fixable in well under a minute.
    """
    project = os.environ.get(PROJECT_ENV, "").strip()
    dataset = os.environ.get(DATASET_ENV, "").strip()
    missing = [
        name
        for name, value in ((PROJECT_ENV, project), (DATASET_ENV, dataset))
        if not value
    ]
    if missing:
        raise ConfigError(
            "Missing required environment variable(s): "
            + ", ".join(missing)
            + ". Set them to your BigQuery project and dataset, for example "
            + f"{PROJECT_ENV}=<your-gcp-project> {DATASET_ENV}=<your-dataset>."
        )
    return project, dataset
