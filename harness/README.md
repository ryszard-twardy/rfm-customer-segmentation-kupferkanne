# KPI parity regression harness

A reusable safety net for the Kupferkanne pipeline. It snapshots the canonical
KPIs to a versioned baseline (`baseline`) and re-verifies them later with
zero-drift assertions (`verify`). Use it before and after any change that could
move the numbers (for example the snake_case rename in issue #9) to prove the
pipeline still produces identical figures.

## What it checks

Primitives (sourced from the curated order-grain table `sales_curated` and the
line-grain view `v_items_for_bi`):

| KPI | Definition | Expected (production) |
|---|---|---|
| `total_revenue` | `ROUND(SUM(order_value), 2)` | 8531365.52 |
| `total_profit` | `ROUND(SUM(order_profit), 2)` | 5100089.72 |
| `distinct_customers` | `COUNT(DISTINCT customer_id)` | 14967 |
| `distinct_orders` | `COUNT(DISTINCT order_id)` | 168777 |
| `grain_parity` | orders present on exactly one grain (order vs line aggregated to order) | 0 |

Derived (computed at comparison time, not stored as primitives):

| KPI | Definition | Expected |
|---|---|---|
| `aov` | `total_revenue / distinct_orders` | 50.55 |
| `margin_pct` | `total_profit / total_revenue * 100` | 59.78 |

The expected values are the harness's own correctness test. When you run
`baseline`, the captured figures must equal them exactly (counts exact, money
exact to the cent, ratios to 2 dp). If a captured value differs, the query is
wrong - fix the query, never edit the expected value.

## Required environment

BigQuery target is read from environment variables only (no ids are hardcoded):

| Variable | Meaning |
|---|---|
| `KK_BQ_PROJECT` | BigQuery project id (for example `<your-gcp-project>`) |
| `KK_BQ_DATASET` | BigQuery dataset holding the curated objects (for example `<your-dataset>`) |

Authentication uses Application Default Credentials. Provide them with either:

- `gcloud auth application-default login`, or
- `GOOGLE_APPLICATION_CREDENTIALS` pointing at a service-account key file.

## Setup (uv, project venv only)

```powershell
uv sync          # install pinned deps into the project .venv
```

No global installs. `pytest` is a dev dependency; `google-cloud-bigquery` is a
runtime dependency, both pinned in `uv.lock`.

## Usage

```powershell
$env:KK_BQ_PROJECT = "<your-gcp-project>"
$env:KK_BQ_DATASET = "<your-dataset>"

# Capture a baseline (self-validates against the expected values above).
uv run python -m harness baseline

# Later, after any pipeline change, assert zero drift vs the latest baseline.
uv run python -m harness verify
```

`verify` exits 0 on zero drift and non-zero if any KPI moved, so it slots into
CI or a pre-merge check. Baselines are written to
`harness/baselines/kpi_baseline_<YYYY-MM-DD>.json` and committed, each recording
the captured values, every query's SHA-256, and the source object names.

## Tests

```powershell
uv run pytest
```

The tests cover the pure comparison and derivation logic with mock data - they
do not touch BigQuery and need no credentials.
