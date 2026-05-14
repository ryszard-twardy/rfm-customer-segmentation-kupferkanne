# 0003 – Pipeline Order: EDA Before Transform

**Status**: Accepted  
**Date**: 2026-05-11

## Context

The initial pipeline placed RFM segmentation (step 02) before any exploratory data analysis (the misnamed "03_eda" step was actually a set of pre-aggregated BI marts, not exploration). This meant RFM design decisions – `NTILE(5)` quintile choice, the use of `MAX(OrderDate)` as recency anchor, the six-segment threshold bands – were made before the underlying data distributions were ever inspected.

Standard data engineering practice places EDA between cleaning and transformation. Transformation decisions should be informed by observed distribution shape, not by assumption.

## Decision

Reorder the pipeline to: **audit → standardise → clean → validate → EDA → transform → line-grain BI fact → analytics marts**.

The eight SQL files reflect this order via their numeric prefixes:

1. `00_0_data_quality_audit_raw_kupferkanne_2026.sql`
2. `00_1_standardize_dimensions_kupferkanne_2026.sql`
3. `01_0_data_cleaning_pipeline_kupferkanne_2026.sql`
4. `01_1_post_clean_validation_kupferkanne_2026.sql`
5. `02_eda_kupferkanne_2026.sql` – true exploratory views, prefix `eda_`
6. `03_rfm_pipeline_kupferkanne_2026.sql` – RFM informed by EDA findings
7. `04_items_for_bi_kupferkanne_2026.sql`
8. `05_analytics_marts_kupferkanne_2026.sql` – pre-aggregated BI views

## Consequences

- Eight EDA views (distribution, outliers, country breakdown, monthly pattern, frequency, recency, Pareto, basket composition) run on cleaned staging data and inform RFM thresholds.
- The misnamed "EDA" step is renamed `analytics_marts` and moved to step 05 to reflect what it actually does (pre-aggregated BI consumption layer).
- File numbering is now stable: each number maps to a logical phase.
- Code comments in `03_rfm_pipeline` reference the relevant `eda_*` views to make the EDA→design dependency explicit to readers.

## Alternatives Considered

- **Keep the old order, just rename the misleading file** – rejected because it leaves an architectural smell: design decisions made without exploration.
- **Move all EDA to a Quarto notebook only** – rejected because notebooks complement but don't replace queryable SQL views. The views are inspectable in BigQuery, joinable, and reproducible without a runtime.
