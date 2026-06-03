# Kupferkanne – Retail Analytics Platform

[![Status](https://img.shields.io/badge/status-v1.0.2-blue)](CHANGELOG.md)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![BigQuery](https://img.shields.io/badge/warehouse-BigQuery-4285F4)](docs/architecture.md)
[![Power BI](https://img.shields.io/badge/BI-Power%20BI-F2C811)](pbix/)
[![SQLFluff](https://img.shields.io/badge/SQL-lint--clean-success)](.sqlfluff)

End-to-end retail analytics platform for **Kupferkanne**, a fictional Erlangen-based direct-to-consumer e-commerce brand operating across nine European markets. The platform answers three commercial questions: which customers to invest in (segmentation), which products and brands drive profitability, and how much revenue sits at churn risk.

## Overview

```
┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐
│  synth-datagen   │───▶│    BigQuery      │───▶│   Power BI       │
│  (Python CLI)    │    │  data warehouse  │    │   Desktop        │
│                  │    │  + 8-step SQL    │    │   (Import mode)  │
└──────────────────┘    └──────────────────┘    └──────────────────┘
   80 CSV files            30 BQ objects          6-page dashboard
   ~440K records          (11 tables + 19 views)  36+ DAX measures
```

- **39 months** of order data (2023-01 to 2026-03), ~169K orders from ~15,000 customers.
- **Eight-step SQL pipeline** on Google BigQuery, idempotent, lint-clean, with explicit exception policy.
- **Dual-grain Kimball star schema**: order-grain `sales_curated` (~169K) for revenue and segmentation, line-grain `v_items_for_bi` (~275K) for product detail.
- **RFM customer segmentation** with `NTILE(5)` quintiles, six segments derived from composite score 3–15.
- **Power BI Import-mode dashboard** with six pages and 36+ DAX measures.

## Tech stack

| Layer | Tool | Purpose |
|---|---|---|
| Data generation | [synth-datagen](https://github.com/ryszard-twardy/synth-datagen) | Python 3.12 CLI producing realistic data with intentional quality issues |
| Data warehouse | Google BigQuery (GoogleSQL) | Serverless, sharded fact tables, free-tier compatible |
| Transformation | 8-step SQL pipeline | Idempotent (`CREATE OR REPLACE`), lint-clean |
| Linting | SQLFluff 4.1.0 | BigQuery dialect, custom rule policy |
| BI | Power BI Desktop (Import) | Six-page dashboard, dual-grain semantic model |
| DAX formatting | [daxformatter.com](https://www.daxformatter.com/) | SQLBI short-line conventions |

## Repository structure

```
rfm-customer-segmentation-kupferkanne/
├── README.md                  This file
├── CHANGELOG.md               Release notes
├── LICENSE
├── .gitignore
├── .sqlfluff                  Linter config (BigQuery dialect)
│
├── docs/                      Public documentation
│   ├── architecture.md        System overview, tech stack, pipeline flow
│   ├── data_model.md          Kimball star schema, ERD, dual-grain layer
│   ├── methodology.md         RFM approach, EDA, margin, validation
│   ├── measures.md            DAX measure catalogue
│   ├── glossary.md            Domain terminology
│   └── adr/                   Eight Architecture Decision Records
│
├── sql/                       Eight-step pipeline (idempotent, lint-clean)
├── pbix/                      Canonical Power BI file
├── theme/                     Power BI theme JSON
├── data/                      Eighty monthly CSV shards from synth-datagen
├── scripts/                   Python ingest utility
├── graphics/                  Fluent UI icons + attribution
├── tools/                     SQL blank-line analyzer (lint helper)
└── screenshots/               Dashboard previews
```

`data/` contains 80 monthly CSV shards from `synth-datagen`, used as raw input for the BigQuery ingestion script. The cleaning, staging, and curation layers live in BigQuery (`kupferkanne-2026.sales`), not on the filesystem.

## SQL pipeline

The pipeline runs in eight numbered steps. Each step is idempotent (`CREATE OR REPLACE` for views, `DROP+CREATE` for partitioned tables) so the full chain is re-runnable from any point.

| # | Script | Purpose | Output |
|---|---|---|---|
| 1 | `sql/00_0_data_quality_audit_raw_kupferkanne_2026.sql` | Pre-clean audit (29 checks) | `data_quality_audit_raw` |
| 2 | `sql/00_1_standardize_dimensions_kupferkanne_2026.sql` | Dimension standardisation | `v_dim_customers_std`, `v_dim_products_std` |
| 3 | `sql/01_0_data_cleaning_pipeline_kupferkanne_2026.sql` | Parallel cleaning streams | 7 staging tables + `cleaning_log` |
| 4 | `sql/01_1_post_clean_validation_kupferkanne_2026.sql` | Post-clean audit (same 29 checks) | `data_quality_audit_cleaned` |
| 5 | `sql/02_eda_kupferkanne_2026.sql` | Eight EDA views | `eda_*` views |
| 6 | `sql/03_rfm_pipeline_kupferkanne_2026.sql` | Order-grain curation + NTILE(5) RFM scoring | `sales_curated`, `rfm_customer_segments`, `v_rfm_for_bi` |
| 7 | `sql/04_items_for_bi_kupferkanne_2026.sql` | Line-grain fact view | `v_items_for_bi` |
| 8 | `sql/05_analytics_marts_kupferkanne_2026.sql` | Six pre-aggregated BI views | `v_monthly_revenue`, `v_product_performance`, `v_brand_profitability`, `v_regional_performance`, `v_category_monthly_trend`, `v_country_summary` |

**Why EDA before RFM transform**: exploratory analysis informs segmentation design (NTILE bucket count, recency anchor, outlier handling). The pipeline runs EDA on cleaned staging data before the RFM transform, not after. See [ADR 0003](docs/adr/0003-pipeline-order-eda-before-transform.md).

## Architecture Decision Records

Strategic decisions follow the [Michael Nygard format](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions): Context, Decision, Consequences, Alternatives.

| # | Title |
|---|---|
| [0001](docs/adr/0001-end-to-end-engineering-as-operating-standard.md) | End-to-end engineering as operating standard |
| [0002](docs/adr/0002-bigquery-as-data-warehouse.md) | BigQuery as data warehouse |
| [0003](docs/adr/0003-pipeline-order-eda-before-transform.md) | Pipeline order: EDA before transform |
| [0004](docs/adr/0004-star-schema-with-conformed-dimensions.md) | Star schema with conformed dimensions |
| [0005](docs/adr/0005-dual-grain-fact-model.md) | Dual-grain fact model (order + line) |
| [0006](docs/adr/0006-rfm-segmentation-with-ntile.md) | RFM segmentation with `NTILE(5)` |
| [0007](docs/adr/0007-two-tier-margin-calculation.md) | Two-tier margin calculation |
| [0008](docs/adr/0008-synthetic-data-with-realistic-quality-issues.md) | Synthetic data with realistic quality issues |

## Reproducibility

The Python environment for the ingest utility is managed with [uv](https://docs.astral.sh/uv/) and pinned to Python 3.12 (`pyproject.toml` + `uv.lock`).

1. **Set up the Python environment** (creates `.venv` from the lock file):
   ```bash
   uv sync
   ```
2. **Authenticate to Google Cloud** with Application Default Credentials:
   ```bash
   gcloud auth application-default login
   ```
3. **Raw data**: the 80 monthly CSV shards are committed in `data/`, so no generation step is required. To regenerate them from scratch instead, use the companion [synth-datagen](https://github.com/ryszard-twardy/synth-datagen) CLI:
   ```bash
   pip install synth-datagen
   synth-datagen --scenario retail --seed <SEED>
   ```
4. **Ingest into BigQuery** with schema enforcement (defaults shown; override with flags):
   ```bash
   uv run python scripts/upload_to_bigquery_schema_enforced.py --data-dir ./data --project kupferkanne-2026 --dataset sales
   ```
5. **Run the SQL pipeline** in step order, from `00_0` through `05_analytics_marts` (see the SQL pipeline table above). Each script is idempotent; downstream steps consume upstream outputs by name.
6. **Open** `pbix/Kupferkanne-rfm-customer-segmentation.pbix` in Power BI Desktop and refresh against your BigQuery dataset.

The full dataset is regenerable from a single seed value; pipeline runs are byte-identical given the same inputs.

## Dashboard preview

The Power BI dashboard spans six pages: Executive overview, Customer Segments, Products, Churn and Reactivation, Regional, Drillthrough. Screenshots will be added to `screenshots/` as pages reach final polish. The canonical `.pbix` lives in `pbix/Kupferkanne-rfm-customer-segmentation.pbix`.

A web-published version will be hosted on [NovyPro](https://novypro.com/profile_projects/ryszard-twardy) after the dashboard completes.

## Roadmap

- **v1.1.0** – Quarto analytical notebook (`eda_kupferkanne.qmd`) companion to the SQL EDA views, rendered to HTML and published via GitHub Pages.
- **v1.2.0** – TMDL / `.pbip` export of the Power BI model for text-based version control; Pages 5 and 6 build completion.
- **Considered**: pipeline orchestration via Dataform or scheduled queries; `dbt` migration; Sankey migration-flow visual on Page 5.

See [CHANGELOG.md](CHANGELOG.md) for full history.

## Documentation map

- [Architecture](docs/architecture.md) – system overview, tech stack, pipeline flow.
- [Data model](docs/data_model.md) – Kimball star schema, ERD, dual-grain layer.
- [Methodology](docs/methodology.md) – RFM approach, EDA, margin, validation.
- [Measures](docs/measures.md) – DAX measure catalogue.
- [Glossary](docs/glossary.md) – domain terminology.
- [ADRs](docs/adr/) – eight Architecture Decision Records.

## About

Built by **Ryszard Twardy**. Connect on [LinkedIn](https://linkedin.com/in/ryszard-twardy/) or browse other projects on [NovyPro](https://novypro.com/profile_projects/ryszard-twardy).

Companion data generator: [synth-datagen](https://github.com/ryszard-twardy/synth-datagen).

## License

[MIT](LICENSE).
