# AGENTS.md

Master configuration for `rfm-customer-segmentation-kupferkanne`. Read this file first when starting any session.

## Project

- **Name**: rfm-customer-segmentation-kupferkanne
- **Stack**: data
- **Owner**: Ryszard Twardy ([LinkedIn](https://www.linkedin.com/in/ryszard-twardy/))
- **Status**: v1.1.0 tagged; Customer Drillthrough page and Quarto analytical notebook ahead (see `CHANGELOG.md`).
- **Primary objective**: RFM (Recency, Frequency, Monetary) customer segmentation for Kupferkanne e-commerce – BigQuery modeling + Power BI BI layer + Python pipelines.

## Repository layout

| Location | Purpose |
|---|---|
| `sql/` | BigQuery pipeline and view DDL. |
| `pbip/` | Power BI project: TMDL semantic model and report definition. |
| `harness/` | Python KPI-parity harness (checks the model against BigQuery baselines); see `harness/README.md`. |
| `notebooks/` | Quarto analytical notebook. |
| `docs/` | Reviewer-facing narrative. |
| `docs/adr/` | Architectural Decision Records. |
| `.specify/memory/constitution-data.md` | Stack-specific invariants. |

## Checks

- SQL lint: `sqlfluff lint sql/ --dialect bigquery`
- KPI-parity harness: see `harness/README.md`.

## Issue tracker

GitHub Issues, operated via the `gh` CLI.

## Architectural decisions

Recorded as ADRs in `docs/adr/`.

## Conventions

- **Typography**: en-dash `–` (never em-dash `U+2014`), ASCII quotes only, backticks for code/paths/identifiers.
- **Filesystem**: dot-prefix everywhere; underscore-prefixed directory names are legacy and must not appear.
- **Report/model edits**: visual and report JSON edits are scripted; see `scripts/`.
- **Backups**: `$env:PROJECTS_ROOT\.backups\rfm-customer-segmentation-kupferkanne\` (outside repo, per-machine).
- **Cross-machine**: this repo syncs via git.
