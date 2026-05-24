# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.1] – 2026-05-24

Model-hygiene release. Five SQLBI / Best Practice Analyzer findings resolved (F003, F004, F006, F007, F008) plus one bundled DAX-formatting fix (F028). All changes are metadata-only: no measure expressions altered, no folder structure changed, no SQL pipeline touched. `[Total Revenue]`, `[Total Profit]`, and the dual-grain Grain Reconciliation invariant all preserved.

### Added

- `tools/format_string_batch.csx` — Tabular Editor 2 C# script for FormatString normalization across 32 measures (F003)
- `tools/format_summarize_by_batch.csx` — Tabular Editor 2 C# script for `SummarizeBy = None` batch across 33 columns (F006)
- `tools/queries/` — five reusable DAX diagnostic queries: `info_measures_export`, `diag_grain_reconciliation`, `diag_kpi_values`, `diag_segment_filter_test`, `diag_cols_hidden_check`

### Changed

- `docs/measures.md` → v7, synced with the BPA batch per the atomic-invariant rule (BPA changes and docs land in the same session)
- 32 measures: FormatString normalized to SQLBI gold standard — Currency `"€"#,##0.00;-"€"#,##0.00`, Percentage `0.00%`, Count `#,##0`, Decimal `0.00`, Date `dd-mmm-yyyy` (F003, issue #1)
- 4 calculated tables: DAX expressions reformatted per SQLBI / daxformatter.com short-line gold standard — `dim_SegmentOrder`, `dim_SegmentActions`, `Reactivation Rate`, `dim_KPI_Selector` (F028, bundled with F003)
- 33 columns: `SummarizeBy = None` to force explicit measure usage and block implicit aggregations from drag-and-drop (F006, issue #4)

### Hidden (UI-only, no functional change)

- 4 fact-source columns: `sales_curated[Order Value]`, `sales_curated[Order Profit]`, `v_items_for_bi[Line Net Amount]`, `v_items_for_bi[Line Profit]` (F004, issue #2)
- 10 foreign key columns: `Customer ID`, `Order ID`, `Order Date`, `Product ID`, `Segment` across `sales_curated`, `v_items_for_bi`, `v_rfm_for_bi`, `v_dim_customers_std`, `dim_SegmentOrder` — defensive star-schema UX per Kimball / SQLBI; canonical access via dimensions (F007, issue #5)

### Removed

- Inactive auto-detected relationship `v_items_for_bi[Order ID]` → `sales_curated[Order ID]`. No DAX expression activated it via `USERELATIONSHIP()`. Cross-fact reconciliation is performed by the `[Grain Reconciliation]` measure (invariant = 0), not by a model relationship. (F008, issue #6)

### Deferred to v1.1

- **F005**: Float → Fixed Decimal conversion for 16 numeric columns. Type change has measure-recompute and storage-format implications; warrants a dedicated session with full regression suite.
- **F033**: `dim_SegmentActions` Power Query M-code refresh bug — M code references column `EmailFrequency` but model column is `Email Cadence`; Refresh All fails. Model functions without Refresh as data is pre-loaded.

### Documentation

- v7 of `docs/measures.md` adds four cross-cutting sections — **Format String Standards**, **Column Behavior: SummarizeBy = None**, **Foreign Key Visibility**, **Hidden Fact Columns** — plus a "Fact-to-fact joins explicitly NOT used" sub-section under Relationships. D028 dual-grain customer satellite documented as the explicit exception to the FK-hide policy.
- Two new diagnostic lessons logged in audit findings:
  - **F031** — Power BI Desktop's DAX query view returns an empty `[FormatString]` column from `INFO.VIEW.MEASURES()` even when format strings are applied. Verify measure metadata via the Tabular Editor 2 Properties panel, not the DAX view.
  - **F032** — Tabular Editor 2's "Rules for the local user" BPA collection sometimes fails to persist across restarts. Re-import the ruleset from URL or fall back to a local file.

### Internal

- `_checkpoints/` → `.checkpoints/` migration completed (gitignored, workflow v3 atomic invariant)
- Workflow v3 stack consolidated: atomic per-finding commits (one per issue, with `Closes #N` trailer), `/mp-to-issues` skill adopted for tracer-bullet issue creation, GitHub Projects v2 board with cached field/option IDs for skill consumption
- New TE2 batch-script hygiene rule: pattern-matching scripts require `dryRun = true` default, explicit manual-override list, and `INFO.VIEW.*` pre-flight introspection
- New rule on TE2 C# Roslyn compatibility: use `KeyValuePair<string, string>` instead of value tuples (TE2's embedded Roslyn predates C# 7.0)

---

## [1.0.0] – 2026-05-12

First public release. Complete data warehouse with eight-step SQL pipeline on BigQuery, dual-grain dimensional model, RFM customer segmentation, and a Power BI Import-mode dashboard. Five core documentation files plus eight Architecture Decision Records describe the design.

### Added

- **Eight-step idempotent SQL pipeline** on BigQuery (`kupferkanne-2026.sales`): raw audit, dimension standardisation, parallel cleaning streams, post-clean validation, EDA, RFM transform, line-grain BI fact, analytics marts. All scripts pass `sqlfluff lint` with documented exception policy for UNION ALL audit blocks.
- **`02_eda_kupferkanne_2026.sql`** – eight exploratory data analysis views (`eda_order_value_distribution`, `eda_order_value_outliers`, `eda_country_breakdown`, `eda_monthly_temporal_pattern`, `eda_customer_frequency_distribution`, `eda_recency_distribution`, `eda_pareto_concentration`, `eda_basket_composition`) inserted **before** RFM transform so segmentation thresholds are informed by observed distributions.
- **Dual-grain BI semantic layer**: `sales_curated` (order-grain, ~169K rows) for revenue and segmentation; `v_items_for_bi` (line-grain view, ~275K rows) for product-level detail. Measure naming convention enforces grain at consumption time (`[Total *]` vs `[Line *]`).
- **`rfm_customer_segments` table** scoring 14,900 customers via `NTILE(5)` quintiles, composite score 3–15, six business-meaningful segments (Champions, Loyal Customers, Potential Loyalists, Recent Customers, At Risk, Hibernating). Recency anchored on `MAX(OrderDate)` rather than `CURRENT_DATE()` for reproducibility.
- **Public documentation suite** under `docs/`: `architecture.md`, `data_model.md`, `methodology.md`, `measures.md`, `glossary.md` plus eight Architecture Decision Records in `docs/adr/` following Michael Nygard format.
- **Eight Architecture Decision Records**: end-to-end engineering as operating standard, BigQuery as data warehouse, pipeline order with EDA before transform, star schema with conformed dimensions, dual-grain fact model, RFM segmentation with NTILE, two-tier margin calculation, synthetic data with realistic quality issues.
- **Synthetic dataset** (~440K records across 80 CSV shards) generated by companion tool [synth-datagen](https://github.com/ryszard-twardy/synth-datagen) with documented quality issues (duplicate orders, cents-format inconsistency, orphan keys, type drift, header-row contamination) for genuine cleaning-pipeline work.
- **Power BI dashboard** (Import mode) connected to BigQuery, themed with custom JSON, supporting six analytical pages.

### Changed

- **Pipeline order corrected**: EDA inserted as step 5 (between validation and RFM transform); pre-aggregated marts moved to terminal step 8. Previous order ran RFM transform before any documented exploration.
- **File renames** for clarity: `02_rfm_pipeline_*` → `03_rfm_pipeline_*` (now post-EDA), `03_sales_analytics_*` → `05_analytics_marts_*` (terminal BI consumption layer).
- **`sales_curated` redefined** from line-grain view (~275K rows) to order-grain table (~169K rows) per dual-grain decision. Line-grain detail now lives in dedicated view `v_items_for_bi`.
- **Architectural rule added** (`[Total *]` measures source from order-grain `sales_curated` only; `[Line *]` from `v_items_for_bi`).
- **DAX measures refactored** to fact-grain sourcing principle; dimensional views serve as drill-down axes and legends only.

### Removed

- `v_product_analytics` removed from Power BI semantic layer (redundant with `v_items_for_bi`). View retained in BigQuery for ad-hoc SQL.
- Six pre-aggregated marts (`v_monthly_revenue`, `v_product_performance`, `v_brand_profitability`, `v_regional_performance`, `v_category_monthly_trend`, `v_country_summary`) removed from Power BI semantic layer; replaced by DAX over fact tables. Retained in BigQuery as documented BI artifacts.
- DDL `PARTITION BY` removed from staging tables. Conflict with window-function `PARTITION BY` in `ROW_NUMBER()` dedup caused 96% data loss in pre-fix iteration; `CLUSTER BY` retained for cost optimisation.

### Fixed

- Git history reset to single commit on fresh `main` branch (renamed from `master`); v1.0.0 tag applied. Clean history beats preserved iteration for first public release.
- All Markdown links across `docs/` and `docs/adr/` verified for integrity; broken cross-references corrected.
- Identifier casing made consistent across SQL, DAX, and documentation: source columns preserved verbatim (`CustomerID`, `OrderID`, `LineNetAmount`).
- Documentation cleaned of internal rule and decision identifiers (R### and D### references); these now live exclusively in internal continuity files.

### Documentation

- Five core documents written from scratch or rewritten for v1.0.0:
  - `architecture.md` – system overview, tech stack, pipeline flow, documentation map.
  - `data_model.md` – Kimball star schema with ERD and dual-grain semantic layer.
  - `methodology.md` – approach, EDA, RFM segmentation, margin calculation, validation.
  - `measures.md` – DAX measure catalogue.
  - `glossary.md` – 20-term reviewer-facing glossary.
- Eight ADRs document strategic decisions in Michael Nygard format with Context, Decision, Consequences, and Alternatives.
- DAX style conventions documented as the SQLBI short-line standard (Marco Russo and Alberto Ferrari), with `daxformatter.com` applied before commit.

### Quality

- `sqlfluff` 4.1.0 BigQuery dialect adopted as SQL quality gate. All eight pipeline files pass `sqlfluff lint sql/`. Acceptable AL03/AM06/RF02/RF04 violations within UNION ALL audit blocks documented as exception policy in internal rules.
- Manual blank-line restoration pass after `sqlfluff fix` to preserve readability (the linter does not preserve blank lines before CREATE/CTE/VALIDATION SELECT blocks).
- Pre/post-clean audit checks (29 each) bookend the cleaning step. Both write findings to BigQuery audit tables for inspection. Pipeline documents issues rather than aborting.

### Architecture

- Repository structured for Mode B continuity: public `docs/` for polished narrative, private `_checkpoints/` (gitignored) for AI-continuity living documents. Strict separation: hiring-manager value goes public, work-in-progress stays local.
- ADR set established as the authoritative record of strategic decisions; ADRs are short, dated, and frozen once accepted.

---

## Pre-1.0.0 development

This release consolidates four months of iteration that pre-dates the v1.0.0 tag. Historical context:

- **April 2026** – initial architecture lock: star schema, RFM methodology with NTILE quintiles, weighted margin principle, dual-grain semantic layer designed during page-by-page Power BI build.
- **Early May 2026** – sqlfluff adoption as SQL quality gate; lint exception policy documented; baseline tag pre-restructure.
- **Mid May 2026** – pipeline reorder (EDA before transform), eight ADRs drafted, public documentation rewritten from scratch, internal continuity files moved to `_checkpoints/`.
- **2026-05-12** – v1.0.0 ship: git reset, ADR audit (production-decision voice over portfolio-piece framing), documentation final pass, tag.

Earlier iteration history is preserved in `_checkpoints/CHECKPOINT_*.md` (local only, gitignored).

---

## Roadmap

### [1.1.0] – planned post-Power BI dashboard ship

- **Quarto analytical notebook** (`eda_kupferkanne.qmd`) as companion to the SQL EDA views, rendered to HTML and published via GitHub Pages at `ryszard-twardy.github.io/rfm-customer-segmentation-kupferkanne`.
- New ADR documenting the analytical notebook decision.

### [1.2.0] – planned

- **TMDL / `.pbip` export** of the Power BI model for text-based version control and review.
- Power BI Page 5 (Lifecycle Intelligence) and Page 6 (Drillthrough) build completion.

### Considered, not committed

- Pipeline orchestration via Dataform or scheduled queries (currently runs manually per session).
- `dbt` migration (would require `.sqlfluff` config harmonisation).
- Sankey migration-flow visual on Page 5, gated by synthetic-data behavioural verification.

---

[1.0.1]: https://github.com/ryszard-twardy/rfm-customer-segmentation-kupferkanne/releases/tag/v1.0.1
[1.0.0]: https://github.com/ryszard-twardy/rfm-customer-segmentation-kupferkanne/releases/tag/v1.0.0
