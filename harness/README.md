# KPI parity regression harness

A reusable safety net for the Kupferkanne pipeline. `verify` re-runs the
canonical KPI queries and asserts zero drift against the committed baseline.
`baseline` shows how the figures moved against it, and only
`baseline --accept --reason` writes a new baseline. Use it before and after any
change that could move the numbers (for example a column rename) to prove the
pipeline still produces identical figures, or to record why they moved.

## What it checks

Primitives (sourced from the curated order-grain table `sales_curated` and the
line-grain view `v_items_for_bi`):

| KPI | Definition | Compared |
|---|---|---|
| `total_revenue` | `ROUND(SUM(order_value), 2)` | to the cent |
| `total_profit` | `ROUND(SUM(order_profit), 2)` | to the cent |
| `distinct_customers` | `COUNT(DISTINCT customer_id)` | exactly |
| `distinct_orders` | `COUNT(DISTINCT order_id)` | exactly |
| `grain_parity` | orders present on exactly one grain (order vs line aggregated to order); 0 = parity | exactly |

Derived (computed at comparison time, not stored as primitives):

| KPI | Definition | Compared |
|---|---|---|
| `aov` | `total_revenue / distinct_orders`, 2 dp half-up | to the cent |
| `margin_pct` | `total_profit / total_revenue * 100`, 2 dp half-up | to the cent |

The values live in one place, `harness/baselines/kpi_baseline.json`. It changes
only through `baseline --accept --reason` (see Changing a baseline); never edit
it by hand.

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

# After any pipeline change, assert zero drift vs the baseline.
uv run python -m harness verify

# Show what a new baseline would change, old -> new (writes nothing).
uv run python -m harness baseline

# Accept the new figures and record why they moved.
uv run python -m harness baseline --accept --reason "<why the figures moved>"
```

`verify` exits 0 on zero drift and non-zero if any KPI moved, so it slots into
CI or a pre-merge check. The baseline is committed and records the captured
values, the capture time, every query's SHA-256 and the source object names.
`verify` compares the values only; it does not check the stored hashes.

## Changing a baseline

Never edit a baseline file by hand. A baseline changes only through
`baseline --accept --reason "<why>"`:

- It runs the same queries and the same comparison as `verify`, and prints the
  old -> new value of each changed KPI plus the count of unchanged ones.
- It also lists each KPI query whose stored SHA-256 is no longer current.
- It rewrites the baseline in place (temp file, then rename) with the same key
  order and formatting. Unchanged KPIs keep their stored values; every
  metadata field is rebuilt, so `captured_at_utc` and the query hashes describe
  the new values. The git diff shows only what moved.
- It appends one JSON line to `harness/baselines/accept_log.jsonl`: the UTC
  time, the git HEAD and whether tracked files had uncommitted changes, the
  reason, each changed KPI's old and new value, and the old and new SHA-256 of
  each query whose hash changed.
- It replaces the baseline first and appends the log line after it, so a run
  that stops between the two leaves the new baseline without its log line;
  check that both files changed before committing.
- An empty or whitespace-only reason, `--accept` without `--reason`, or
  `--reason` without `--accept` exits 2 and writes nothing.
- If no KPI value and no query hash changed, it says so, writes nothing and
  exits 0.

Without `--accept`, `baseline` prints the same diff and writes nothing. When no
baseline exists yet, `--accept` writes the first one. The file name carries no
date: the accept log and git history record when each change landed.

## Tests

```powershell
uv run pytest
```

The tests cover the comparison and derivation logic and both `baseline` modes,
using synthetic figures and a fake query layer – they do not touch BigQuery and
need no credentials.
