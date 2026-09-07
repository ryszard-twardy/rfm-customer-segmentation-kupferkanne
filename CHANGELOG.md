# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added

- Year-over-year and prior-year measures for Profit and Profit Margin, plus a prior-year Revenue measure, in the `04 - Time Intelligence` folder.
- Customer Drillthrough (Page 7) built as a hidden, entry-wired drill target reached through customer-level measures.
- Two Architecture Decision Records: analytical notebook with Quarto (ADR 0009) and Deneb Vega-Lite regional map (ADR 0014).
- Quarto analytical EDA notebook (`notebooks/eda_kupferkanne.qmd` plus project config) as a reasoning companion to the SQL EDA views.
- All visual titles and subtitles converted to dynamic, measure-driven DAX bound through the format pane, so headings track the active filter context.
- Revenue Rolling 12M measure for trailing-twelve-month revenue on the Executive Summary trend.
- Brand logo applied across all seven report pages.

### Changed

- Root `README.md` rewritten as a reviewer-facing landing page: answer-first structure (problem, system, method, seven report pages, engineering standards, repository map, reproduction, scope) replacing the prior tech-stack-first layout.
- Factual claims reconciled against serialized state and live BigQuery: 109 DAX measures, 12 tables, 7 single-direction relationships (0 bidirectional), 6 product categories, ~460K source records, and the equal-weight brand margin corrected to 59.94% (weighted 59.78%).
- Report page names verified from `page.json` (Page 6 = Regional Analysis); status badge aligned to the latest release tag v1.1.0.
- EDA notebook fix pass and table presentation polish: author attribution, resolved WIP markers, corrected Quarto project note, 2-decimal formatting, suppressed index, Title-Case headers, percent and currency formats
- README: added an "Engineering workflow" section describing the operator-gated, AI-assisted development process.
- Loader sets no default table or partition expiration on a dataset it creates, and reports when the dataset it targets already carries one.

---

## [1.1.0] – 2026-07-09

Power BI dashboard build-out and semantic-model consolidation. The report reaches its full seven-page structure and migrates to PBIP / TMDL for text-based version control; the segment and customer dimensions are unified onto `dim_Segment` and `dim_Customer`. All KPI invariants preserved (Total Revenue, Total Profit, and the dual-grain Grain Reconciliation = 0), now guarded by a parity regression harness.

### Added

- Three Power BI pages built out to their full structure: Churn Risk & What-If (Page 4), Customer Lifecycle Intelligence (Page 5), and Regional Analysis (Page 6), alongside a Customer Drillthrough target page.
- Page 5 lifecycle visuals – RFM heatmap, Pareto concentration, cohort-retention heatmap, and a new-vs-returning revenue area chart – plus a Customer Decile column and supporting measures.
- Page 6 regional visuals – adaptive dual-grain choropleth map (Deneb), market-ranking combo chart, and Country / Region slicers – with filter-aware titles driven by a `[Country Filter Active]` measure.
- Two SQL views feeding the lifecycle page, `v_cohort_retention` and `v_revenue_new_returning`, plus `v_dim_customers_for_bi`, a BI-facing customer dimension.
- KPI parity regression harness (baseline capture plus verify) guarding Total Revenue, Total Profit, and the dual-grain Grain Reconciliation invariant across model refactors.
- Churn-risk and median-benchmark measures for Page 4, plus page-subtitle measures across Pages 1, 3, 5, and 6.
- `uv` dependency management for the Python ingest utility (`pyproject.toml` plus `uv.lock`), pinned to Python 3.12.

### Changed

- Power BI project migrated from `.pbix` to PBIP / TMDL format for text-based, reviewable version control; `.gitattributes` and `.git-blame-ignore-revs` added to normalise line endings and stop TMDL CRLF churn.
- Semantic model consolidated: `dim_SegmentOrder` and `dim_SegmentActions` merged into a single `dim_Segment`; RFM segment attributes re-homed onto `dim_Customer`; the customer dimension repointed to `v_dim_customers_for_bi` and renamed `dim_Customer`; `v_dim_products_std` renamed `dim_Product`.
- Product & Brand page (Page 3) rebuilt on the line-grain `v_items_for_bi` model with a weighted Margin Baseline reference.
- Pipeline columns renamed to snake_case end-to-end; a `v_items_for_bi` to `dim_Date` relationship added for date-sliced line-grain analysis; field-visibility and format-string hygiene across the model.
- Deck-wide report hygiene: unified visual padding, standardised Selection-pane group names and z-ordering, pinned subtitle colours and title fonts, and registered AppSource custom visuals.

### Removed

- Legacy `.pbix` report (superseded by the PBIP project) and development-only diagnostic / metadata-export DAX queries.
- `v_rfm_for_bi` retired and its bidirectional customer-satellite relationship dropped in favour of the single-direction topology.
- Duplicate geography columns dropped from the `sales_curated` import.

### Fixed

- Page 6 header corrected to "Regional Analysis"; region drill flags made immune to visual group-by.
- Segment Color measure realigned to the Muted Earth palette with a neutral fallback.
- Partial final month trimmed from the Page 3 category trend via a closed-month flag.

### Documentation

- `measures.md` reconciled to the live post-refactor model: inventory tables rebuilt, stale column and source references corrected, and the internal build changelog and decision identifiers removed to leave a clean reviewer-facing catalogue.
- `architecture.md`, `README.md`, and ADR page-count references reconciled to the live seven-page structure; order-data span corrected to 39 months; synthetic-data cohort-retention limitation documented in `methodology.md`.
- Two new Architecture Decision Records – single-direction customer topology (0012) and unified segment dimension (0013) – supersede 0010 and 0011.

### Internal

- Read-only SessionStart git-state hook (dirty / ahead / behind banner) added.
- SQL lint policy updated (ST06 / ST07 documented as house-style deviations); diagnostic DAX and PBIP scratch-query hygiene; internal workspace cleanup.

---

## [1.0.2] – 2026-05-27

Internal configuration and documentation-hygiene release. No functional, model, SQL, or measure changes; all KPI invariants preserved (Total Revenue, Total Profit, and the dual-grain Grain Reconciliation = 0).

### Internal

- `AGENTS.md` agent-configuration refreshed: project name canonicalised, backups path corrected, and the release-status line synced to the shipped v1.0.1 tag.
- Prose dash characters across `AGENTS.md` normalised to ASCII hyphens for cross-tool consistency.

---

## [1.0.1] – 2026-05-24

Model-hygiene release. Five SQLBI / Best Practice Analyzer findings resolved plus one bundled DAX-formatting fix. All changes are metadata-only: no measure expressions altered, no folder structure changed, no SQL pipeline touched. `[Total Revenue]`, `[Total Profit]`, and the dual-grain Grain Reconciliation invariant all preserved.

### Added

- `tools/format_string_batch.csx` – Tabular Editor 2 C# script for FormatString normalization across 32 measures
- `tools/format_summarize_by_batch.csx` – Tabular Editor 2 C# script for `SummarizeBy = None` batch across 33 columns
- `tools/queries/` – five reusable DAX diagnostic queries: `info_measures_export`, `diag_grain_reconciliation`, `diag_kpi_values`, `diag_segment_filter_test`, `diag_cols_hidden_check`

### Changed

- `docs/measures.md` → v7, synced with the BPA batch per the atomic-invariant rule (BPA changes and docs land in the same session)
- 32 measures: FormatString normalized to SQLBI gold standard – Currency `"€"#,##0.00;-"€"#,##0.00`, Percentage `0.00%`, Count `#,##0`, Decimal `0.00`, Date `dd-mmm-yyyy` (issue #1)
- 4 calculated tables: DAX expressions reformatted per SQLBI / daxformatter.com short-line gold standard – `dim_SegmentOrder`, `dim_SegmentActions`, `Reactivation Rate`, `dim_KPI_Selector` (bundled with the FormatString batch)
- 33 columns: `SummarizeBy = None` to force explicit measure usage and block implicit aggregations from drag-and-drop (issue #4)

### Hidden (UI-only, no functional change)

- 4 fact-source columns: `sales_curated[Order Value]`, `sales_curated[Order Profit]`, `v_items_for_bi[Line Net Amount]`, `v_items_for_bi[Line Profit]` (issue #2)
- 10 foreign key columns: `Customer ID`, `Order ID`, `Order Date`, `Product ID`, `Segment` across `sales_curated`, `v_items_for_bi`, `v_rfm_for_bi`, `v_dim_customers_std`, `dim_SegmentOrder` – defensive star-schema UX per Kimball / SQLBI; canonical access via dimensions (issue #5)

### Removed

- Inactive auto-detected relationship `v_items_for_bi[Order ID]` → `sales_curated[Order ID]`. No DAX expression activated it via `USERELATIONSHIP()`. Cross-fact reconciliation is performed by the `[Grain Reconciliation]` measure (invariant = 0), not by a model relationship. (issue #6)

### Deferred to v1.1

- Float to Fixed Decimal conversion for 16 numeric columns. Type change has measure-recompute and storage-format implications; warrants a dedicated session with full regression suite.
- `dim_SegmentActions` Power Query M-code refresh bug – M code references column `EmailFrequency` but model column is `Email Cadence`; Refresh All fails. Model functions without Refresh as data is pre-loaded.

### Documentation

- v7 of `docs/measures.md` adds four cross-cutting sections – **Format String Standards**, **Column Behavior: SummarizeBy = None**, **Foreign Key Visibility**, **Hidden Fact Columns** – plus a "Fact-to-fact joins explicitly NOT used" sub-section under Relationships. The dual-grain customer satellite is documented as the explicit exception to the FK-hide policy.
- Two new diagnostic lessons logged in audit findings:
  - Power BI Desktop's DAX query view returns an empty `[FormatString]` column from `INFO.VIEW.MEASURES()` even when format strings are applied. Verify measure metadata via the Tabular Editor 2 Properties panel, not the DAX view.
  - Tabular Editor 2's "Rules for the local user" BPA collection sometimes fails to persist across restarts. Re-import the ruleset from URL or fall back to a local file.

### Internal

- Internal working directories consolidated under dot-prefixed, gitignored paths
- Commit discipline consolidated: atomic per-finding commits (one per issue, with `Closes #N` trailer); GitHub Projects v2 board adopted for issue tracking
- New TE2 batch-script hygiene rule: pattern-matching scripts require `dryRun = true` default, explicit manual-override list, and `INFO.VIEW.*` pre-flight introspection
- New rule on TE2 C# Roslyn compatibility: use `KeyValuePair<string, string>` instead of value tuples (TE2's embedded Roslyn predates C# 7.0)

---

## [1.0.0] – 2026-05-14

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
- Documentation cleaned of internal rule and decision identifiers (R### and D### references).

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

- Repository split into a public reviewer-facing layer (`docs/`) and private, gitignored working notes.
- ADR set established as the authoritative record of strategic decisions; ADRs are short, dated, and frozen once accepted.

---

## Pre-1.0.0 development

This release consolidates four months of iteration that pre-dates the v1.0.0 tag. Historical context:

- **April 2026** – initial architecture lock: star schema, RFM methodology with NTILE quintiles, weighted margin principle, dual-grain semantic layer designed during page-by-page Power BI build.
- **Early May 2026** – sqlfluff adoption as SQL quality gate; lint exception policy documented; baseline tag pre-restructure.
- **Mid May 2026** – pipeline reorder (EDA before transform), eight ADRs drafted, public documentation rewritten from scratch.
- **2026-05-14** – v1.0.0 ship: git reset, ADR audit (production-decision voice over portfolio-piece framing), documentation final pass, tag.

---

## Roadmap

### [1.2.0] – planned

- Publish the committed notebook (`notebooks/eda_kupferkanne.qmd`, `_quarto.yml`) to GitHub Pages at `ryszard-twardy.github.io/rfm-customer-segmentation-kupferkanne`; the notebook is authored and the rendered `_site/` is gitignored, so only the gh-pages deploy step is outstanding.

### Considered, not committed

- Pipeline orchestration via Dataform or scheduled queries (currently runs manually per session).
- `dbt` migration (would require `.sqlfluff` config harmonisation).
- Sankey migration-flow visual on Page 5 – considered and dropped after synthetic-data behavioural verification showed the migration signal too weak to justify the visual.

---

[Unreleased]: https://github.com/ryszard-twardy/rfm-customer-segmentation-kupferkanne/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/ryszard-twardy/rfm-customer-segmentation-kupferkanne/releases/tag/v1.1.0
[1.0.2]: https://github.com/ryszard-twardy/rfm-customer-segmentation-kupferkanne/releases/tag/v1.0.2
[1.0.1]: https://github.com/ryszard-twardy/rfm-customer-segmentation-kupferkanne/releases/tag/v1.0.1
[1.0.0]: https://github.com/ryszard-twardy/rfm-customer-segmentation-kupferkanne/releases/tag/v1.0.0
