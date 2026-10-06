# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added

- Brand file `notebooks/_brand.yml` derived from the Power BI theme (the ten data colours, the segment colours and the page and border surfaces), with Lato from Google Fonts as the type, plus `hibernating_focus`, a darker shade of the Hibernating colour that the exhibits use for focus marks so they stand apart from the grey context.
- `notebooks/exhibits_win_back.qmd` with three win-back exhibits (segment shares, margin before and after the discount, contribution per 1,000 EUR of discount), each asserted against the `docs/methodology.md` literals at render time. The page opens with a link back to the analytical notebook and a three-sentence lede whose ratio and discount literals are checked as well. Each chart comes before its table. Shares, margins and realised discounts show at two decimals in the exhibit tables and in the charts' value labels, except the combined At Risk and Hibernating shares on the segment-share chart, which show one decimal; the win-back rates show whole percents. The checks run before any exhibit is written, a failed check stops the render, and the check table closes the page in a collapsed callout. The charts sit in a wide column capped at their 1,200 px canvas (`notebooks/exhibits.css`) and open in a lightbox. Alt texts and the `<title>` and `<desc>` of the embedded SVGs describe each chart with its key values. The segment-share chart uses direct labels and a bracket instead of a legend; its label clearance, like the margin chart's legend spacing, is asserted with DejaVu Sans metrics. The page also asserts that matplotlib lays out the exhibits and rasterises the PNGs in a brand face (Lato), not the DejaVu fallback.
- Six exhibit images under `docs/img/exhibits/`: the three exhibits in an embedded variant (no heading, responsive SVG root) and a titled variant, each saved as SVG and PNG.
- Analytical notebook (`notebooks/eda_kupferkanne.qmd`): its introduction links to the win-back exhibits page, and the page shows a last-modified date.
- A country-coverage assertion as the last numbered pipeline script, with a negative test in `tools/queries/`.
- Harness `baseline` command: baselines change only through the comparison queries, with a stated reason logged on every accept.

### Changed

- `pyyaml` promoted to a direct dependency in `pyproject.toml`; the exhibits document reads the brand file with it.
- The exhibits document added to the Quarto render list in `notebooks/_quarto.yml`; it sets its own output file, so the notebook stays the site landing page.
- Analytical notebook tables show counts with thousands separators, and every table has a numbered, descriptive caption; the monthly revenue chart reads in EUR thousands.
- Win-back figures after the fixes: At Risk retains 1.85 times the contribution per euro of discount that Hibernating retains at the playbook's rates, and about 1.2 times as much with either rate applied to both segments.
- Analytical notebook and win-back exhibits on the rebuilt tables: mean order value 50 EUR, P99 264 EUR with 1,688 orders beyond it, the largest at 3.8 times P99, country averages from 49.57 to 51.43 EUR, a reconciliation baseline of 8,476,200.74 EUR, and the bottom half of customers at about 7% of revenue, corrected from about 10%. The contribution chart's heading reads 2,465 against 1,335 EUR, and its gap label reads "+1,130 EUR (1.85 times as much) at the playbook's rates". The exhibits are laid out and rasterised in Lato, and their SVGs carry the text as glyph paths.

### Removed

- Measures `[Top Category Revenue]` and `[Top Category Name]`: no visual was bound to either and no measure referenced them. Both are removed with their generated Q&A entries, and the model now has 107 measures.

### Fixed

- Theme name in `theme/rfm_dashboard_theme.json` stored an em-dash as a JSON escape; it now decodes to an en-dash and matches the theme registered in the report.
- Dash typography in the analytical notebook (`notebooks/eda_kupferkanne.qmd`): the title, the prose and the population-split table label use en-dashes where spaced hyphens stood in for them.
- ADR links in the analytical notebook point at the repository on GitHub instead of `../docs/adr/`, a path that does not exist on the published site.
- Recency chart in the analytical notebook: the overlapping bucket codes on the axis are replaced with day ranges taken from the recency view (`0–29` to `730+`), and the render asserts that no tick labels overlap. The recency table shows the same ranges next to the codes.
- Analytical notebook charts use the brand type stack from `notebooks/_brand.yml` instead of matplotlib's default DejaVu Sans.
- Cleaning now also reads a line amount as cents when it is at least 10 times its list value; 69 lines in 67 orders had passed as euros. Revenue moves from 8,531,365.52 to 8,476,200.74 EUR, and the figures that derive from it are updated in the docs.
- A fixed as-of date replaces the current date in the raw audit, cleaning and RFM scripts, so re-runs read the same shards and apply the same cut-off.
- Discount bounds test fractions (above 1, not above 100); percentiles are exact (P99 263.70); duplicate rows resolve on an MD5 of the raw row instead of a random UUID.
- The raw audit's shard checks select shards by the suffix the wildcard reads; before, they examined no shard and always passed.
- `[Total Orders]` counts distinct orders in the current filter context instead of summing lifetime order counts from `dim_Customer`, so `[Avg Order Value]` divides period revenue by period orders; on the Customer Drillthrough cards both now follow a month or order selection. Unfiltered totals are unchanged (168,777 orders).
- Revenue by Segment on the Executive Summary labels values in millions at two decimals, so At Risk and Hibernating no longer both read "€0.1M"; they read €0.11M and €0.06M.

### Documentation

- Appendix of the analytical notebook (`notebooks/eda_kupferkanne.qmd`): the caching note states what the Quarto project renders and that `freeze` is not enabled; the render step adds the exhibits page and the Lato requirement its font check enforces.
- Win-back recommendation in `docs/methodology.md` reframed as a controlled pilot with a randomised holdout, an incremental primary metric and a decision rule, and extended with scale figures: the two segments' share of scored customers, the revenue at risk and the contribution gained per 1,000 EUR of discount moved.
- Palette description in `docs/architecture.md` corrected to the live theme: muted-blue primary (`#4A7AA0`) on white, with a `#F7F5F1` page background.
- `AGENTS.md` tracker statement matches the repository settings: issue tracking is disabled and planned work is listed under Roadmap in this file.
- Forward note in ADR 0003: the pipeline now has eleven `sql/` scripts, the nine the record lists plus two view scripts.
- Euro format notation in `docs/measures.md` aligned with the model: five measures documented as `€ 0dp` carry a two-decimal format string and now read `€ 2dp`.
- Recorded the likely root cause of the pre-fix staging row loss – sandbox partition expiration rather than a `PARTITION BY` interaction – as a dated note in ADR 0002.
- Page count in `README.md`, `docs/architecture.md` and `docs/methodology.md` aligned to six report pages plus a customer drillthrough: the README heading, the architecture overview, both system diagrams and the lead-in to the methodology page list.
- Known issue recorded in `docs/methodology.md` Limitations: 646 of 168,777 orders fall outside the 0.001 order-value tolerance.
- Appendix with the six-segment share table (customers, share of scored customers, lifetime spend, share of revenue base) added to `docs/methodology.md` as the source of the segment-share exhibit.
- Win-back metric wording in `docs/methodology.md` aligned with the exhibits: At Risk "retains" 1.85 times the contribution per euro of discount that Hibernating retains, instead of "returns", which read as an observed campaign return; the exhibits check that reads the ratio matches the new wording.
- Win-back analysis in `docs/methodology.md`: the 1.85 times ratio is stated at the playbook's rates (15 and 20 percent), with the common-rate comparison (about 1.2 times) and the reversal when the rates are swapped; the pilot, with its metric built from per-customer means, decides Hibernating's rate before the allocation, on the same data: Hibernating is offered 20 and 15 percent against a shared holdout and At Risk 15 percent against its own, and every decision, fixed before launch, keeps the playbook as it is unless a 95 percent bootstrap interval clears its threshold. Hibernating moves to 15 percent if the 15 percent group beats the 20 percent group, per euro of discount if the budget cannot cover every eligible customer and per assigned customer if it can; an offer stops if it falls below break-even; and, if the budget cannot cover everyone and At Risk clears break-even and beats Hibernating, At Risk is contacted first until its pool is exhausted. The recommendation leads with the rate test, the gain per 1,000 EUR of discount moved holds while At Risk customers remain to be contacted, and the deadweight sentence cites At Risk's higher composite RFM score instead of "warmer by definition".
- Win-back exhibits page (`notebooks/exhibits_win_back.qmd`): the lede grows to five sentences, answers its question and states the 1.85 times ratio at the playbook's rates (15 and 20 percent), with the common-rate comparison (about 1.2 times with either rate applied to both segments) and the pilot in `docs/methodology.md`, which tests Hibernating at both rates and, if the budget is short, puts At Risk first only if At Risk retains more on an incremental basis; the contribution-per-1,000-EUR chart scopes its heading, subtitle, caption, description and alt text to the playbook's rates, and its gap label reads "1.85 times" instead of an "x" suffix. The render checks the segment by rate table in `docs/methodology.md` and these literals against the live margins, and asserts that the gap label clears both bars.
- Validation section in `docs/methodology.md` rewritten: grain parity is a semantic-model check, segment monotonicity an observation at the current snapshot with its figures, and country coverage an assertion enforced by the last numbered script. Dated notes in ADRs 0002, 0006, 0007 and 0008 record what the fixes changed, and `harness/README.md` states the order of the baseline and log writes.
- Executive Summary screenshot in `README.md` (`docs/img/exec-summary.png`) replaced with the published report after the fixes; its cards now match the scale table in `README.md`.

---

## [1.2.0] – 2026-09-23

Report completion and public release. The report gains its hidden Customer Drillthrough page and measure-driven titles, the Quarto notebook joins the SQL EDA, the executive analysis ships in `docs/methodology.md` with a quantified win-back recommendation, and the report is public as a live Power BI link with offline assets attached to the release. KPI invariants unchanged (Total Revenue 8,531,365.52, Customers 14,967).

### Added

- Year-over-year and prior-year measures for Profit and Profit Margin, plus a prior-year Revenue measure, in the `04 - Time Intelligence` folder.
- Customer Drillthrough (Page 7) built as a hidden, entry-wired drill target reached through customer-level measures.
- Two Architecture Decision Records: analytical notebook with Quarto (ADR 0009) and Deneb Vega-Lite regional map (ADR 0014).
- Quarto analytical EDA notebook (`notebooks/eda_kupferkanne.qmd` plus project config) as a reasoning companion to the SQL EDA views.
- All visual titles and subtitles converted to dynamic, measure-driven DAX bound through the format pane, so headings track the active filter context.
- Revenue Rolling 12M measure for trailing-twelve-month revenue on the Executive Summary trend.
- Brand logo applied across all seven report pages.
- Architecture Decision Record 0015, warehouse table retention: billing enabled and no dataset-level table or partition expiration.
- Win-back discount allocation analysis in `docs/methodology.md`: revenue base, cost basis and a per-segment derivation behind a quantified recommendation to shift win-back discount budget from Hibernating to At Risk, with its limitations stated.
- Public live report via Power BI publish to web, linked from `README.md`; no sign-in required.
- Offline release assets: the Power BI file with its data (`.pbix`) and a PDF export of the six visible report pages.

### Changed

- Root `README.md` rewritten as a reviewer-facing landing page: answer-first structure (problem, system, method, seven report pages, engineering standards, repository map, reproduction, scope) replacing the prior tech-stack-first layout.
- Factual claims reconciled against serialized state and live BigQuery: 109 DAX measures, 12 tables, 7 single-direction relationships (0 bidirectional), 6 product categories, ~460K source records, and the equal-weight brand margin corrected to 59.94% (weighted 59.78%).
- Report page names verified from `page.json` (Page 6 = Regional Analysis); status badge aligned to the latest release tag v1.1.0.
- EDA notebook fix pass and table presentation polish: author attribution, resolved WIP markers, corrected Quarto project note, 2-decimal formatting, suppressed index, Title-Case headers, percent and currency formats
- README: added an "Engineering workflow" section describing the operator-gated, AI-assisted development process.
- Loader sets no default table or partition expiration on a dataset it creates, and reports when the dataset it targets already carries one.
- `architecture.md` object counts scoped explicitly to the objects the SQL pipeline creates, separating them from the 80 source tables loaded from `data/`.
- Editorial correction in the `architecture.md` overview and the `methodology.md` data-origin paragraph: both now describe the platform and the cleaning pipeline in operational terms.
- `README.md` reproduction steps updated to the current platform configuration: the load step names the loader script and its flags, and the warehouse requires a billing-enabled project with no dataset-level expiration.
- Clarified the v1.1.0 entry for `v_rfm_for_bi`: the retirement removed the table from the Power BI semantic model. The BigQuery view of that name remains in the pipeline, where `v_dim_customers_for_bi` reads it.

### Fixed

- Page 5 subtitle names new vs returning revenue instead of segment migration, which a single-snapshot segment table cannot compute.
- Reset All Filters bookmark re-captured at the clean default state without page navigation, with stale references to a retired mart rebound so Desktop saves no longer re-inject a phantom sort.
- EDA views in `sql/02` rewritten against the post-migration staging schema.

### Documentation

- Analytical claims reconciled with the shipped model: corrected worked margin example in ADR 0007, precise NTILE balance statement, additive-RFM limitation, and Revenue at Risk defined as a value-exposure metric.
- ADR count corrected to fifteen in `README.md` and `architecture.md`.

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

### [1.3.0] – planned

- Publish the analytical notebook, an executive report and a companion deck to GitHub Pages at `ryszard-twardy.github.io/rfm-customer-segmentation-kupferkanne`; all three are rendered locally with Quarto from the committed sources.
- Investigate the 646 orders that fall outside the 0.001 order-value reconciliation tolerance, then fix them or document the cause (known issue in `docs/methodology.md` Limitations).

### Considered, not committed

- Pipeline orchestration via Dataform or scheduled queries (currently runs manually per session).
- `dbt` migration (would require `.sqlfluff` config harmonisation).
- Sankey migration-flow visual on Page 5 – considered and dropped after synthetic-data behavioural verification showed the migration signal too weak to justify the visual.

---

[Unreleased]: https://github.com/ryszard-twardy/rfm-customer-segmentation-kupferkanne/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/ryszard-twardy/rfm-customer-segmentation-kupferkanne/releases/tag/v1.2.0
[1.1.0]: https://github.com/ryszard-twardy/rfm-customer-segmentation-kupferkanne/releases/tag/v1.1.0
[1.0.2]: https://github.com/ryszard-twardy/rfm-customer-segmentation-kupferkanne/releases/tag/v1.0.2
[1.0.1]: https://github.com/ryszard-twardy/rfm-customer-segmentation-kupferkanne/releases/tag/v1.0.1
[1.0.0]: https://github.com/ryszard-twardy/rfm-customer-segmentation-kupferkanne/releases/tag/v1.0.0
