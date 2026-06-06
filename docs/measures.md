# DAX Measures Reference
## Kupferkanne – 36 Measures in 6 Folders + 3 Subtitle Measures + Field Parameter
### Author: Ryszard Twardy
### v7 (2026-05-24) – synced with v1.0.1 BPA batch (F003 format strings, F004 hide fact cols, F006 SummarizeBy=None, F007 hide FKs, F008 remove inactive relationship) per R041 atomic invariant

> Source of truth for all DAX measures. Every table and column name verified against BigQuery SQL scripts (03_rfm_pipeline, 05_analytics_marts). **Since dual-grain D026 (2026-05-07)**, Power BI imports `sales_curated` (order-grain fact table from script 03_rfm_pipeline) as the primary fact source. `v_rfm_for_bi` retained for Customer-grain analytics only. **As of v7 (v1.0.1 BPA batch, 2026-05-24)**, model-wide hygiene policies on FormatString, SummarizeBy, Hidden, and Relationships are documented in the **Model Hygiene** section below.

---

## Data Model: Table → SQL Source Mapping

| Power BI Table | BigQuery Object | Granularity | Key Columns |
|---|---|---|---|
| **sales_curated** | `sales_curated` (TABLE) | **1 row per order (~169K)** | OrderID, CustomerID, OrderDate, OrderValue, OrderCost, OrderProfit, OrderMarginPct, Country, DominantCategory, DominantBrand |
| **v_items_for_bi** | `v_items_for_bi` (VIEW) | **1 row per order line (~275K)** | OrderID, ProductID, CustomerID, OrderDate, Quantity, UnitPrice, LineNetAmount, LineCost, LineProfit, Brand, ProductCategory |
| dim_Customer | `v_dim_customers_for_bi` (VIEW) | 1 row per customer | Customer ID, Full Name, Email, Country, Segment, Recency Days, Order Count, Total Spend, R Score, F Score, M Score, Health Score, Action |
| dim_Product | `v_dim_products_std` (VIEW) | 1 row per product | ProductID, ProductName, Brand, MarginPct |
| dim_Date | DAX CALENDAR | 1 row per day | Date, Year, Month, Year-Month |
| dim_Segment | DAX DATATABLE | 6 rows | Segment, Email Cadence, Loyalty Tier, Discount Approach, Budget Allocation, SortOrder, SegmentColor |
| dim_KPI_Selector | DAX DATATABLE | 5 rows | KPI Name (disconnected) |
| Reactivation Rate | What-If Parameter | auto-generated | Reactivation Rate Value (0–50, step 5) |
*Model also contains `_Measures` (measure container) and `RFM Score Selector` (Field Parameter) - neither has a SQL source. Total model tables: 10.*

**v6 architecture rule (R026):** `[Total Revenue]` and `[Total Profit]` measures pull from fact-grain `sales_curated` ONLY. Dimensional views serve as drill-down axes/legends only – pre-aggregated views break filter context across products/brands/categories.

**Active relationships (5) - verified against `relationships.tmdl`, post-S4 / D060:**
- sales_curated[Customer ID] → dim_Customer[Customer ID] | M:1 | Single
- sales_curated[Order Date] → dim_Date[Date] | M:1 | Single
- v_items_for_bi[Customer ID] → dim_Customer[Customer ID] | M:1 | Single
- v_items_for_bi[Product ID] → dim_Product[Product ID] | M:1 | Single
- dim_Customer[Segment] → dim_Segment[Segment] | M:1 | Single - **R3′, re-pointed onto merged dim_Segment (S4)**

**S3 / D060 (retire `v_rfm_for_bi`):** dropped the table and its 3 relationships – `[Customer ID] ↔ dim_Customer` (Fix-A bidirectional, D046, superseded by D060), `[Last Order Date] → dim_Date`, and `[Segment] → dim_SegmentOrder`. Segment filter propagation is preserved single-direction via R3′ (`dim_Customer[Segment] → dim_Segment[Segment]`). Bidirectional count: 2 → **1**.

**S4 / D060 (merge segment dims):** `dim_SegmentOrder` + `dim_SegmentActions` merged into a single `dim_Segment` (DAX DATATABLE, D074), and R3′ re-pointed onto `dim_Segment[Segment]`. The 1:1 bidirectional was dropped. Bidirectional count: 1 → **0** (D060 end state).

---

## Model Hygiene (v1.0.1 BPA batch, v7)

The following conventions were applied model-wide during the v1.0.1 BPA batch (sessions 2026-05-22 and 2026-05-24, commits `43e4241`, `56eba2c`, `9679a4d`, `0491ed0`, `40f57f3`). They are metadata policies – no measure expressions changed, no folder structure altered. Every measure and column in this document conforms to them.

### Format String Standards (F003)

Per BPA rule **"Provide format string for measures"**, every numeric measure carries an explicit `FormatString`. Conventions (commit `43e4241`):

| Semantic | FormatString | Example measures |
|---|---|---|
| Currency (EUR) | `"€"#,##0.00;-"€"#,##0.00` | `[Total Revenue]`, `[Avg Order Value]`, `[ARPU by Country]` |
| Currency (compact display) | inherited Currency + visual-level "Display units = Millions" | `[Total Revenue]`, `[Total Profit]` on KPI cards |
| Percentage | `0.00%` | `[Profit Margin %]`, `[Revenue % of Total]`, `[Country Revenue Share]` |
| Count (integer) | `#,##0` | `[Total Customers]`, `[Total Orders]`, `[Distinct Orders]` |
| Decimal (small score) | `0.00` | `[Avg R Score]`, `[Avg F Score]`, `[Avg M Score]` |
| Date | `dd-mmm-yyyy` | calc-table date columns |
| Text | *(none – no FormatString applied)* | `[Health Indicator]`, `[Subtitle Page N]`, `[Top Brand Name]` |

**Coverage:** 32 of 46 measures touched by F003. 12 text measures intentionally without format. 3 manual overrides preserved with custom expressions:
- `[Avg Health Score]` → `0.0 "/ 15"` (Score-out-of-15 semantic)
- `[Dynamic KPI Selector]` → format inherited via `SWITCH` from underlying measure
- `[Reactivation Rate Value]` → Integer percentage POINTS, not ratio (custom `0` instead of `0.00%`)

**Batch script:** `tools/format_string_batch.csx` (R043 hygiene: `dryRun=true` default, explicit manual-override helper, BPA pre-flight via `INFO.VIEW.MEASURES()` introspection). Reference implementation for future TE2 pattern-matching batches. BPA delta: "Provide format string for measures" rule 45 → 13 (remaining = 12 text + 1 SWITCH-format, all intentional).

### Column Behavior: SummarizeBy = None (F006, D044)

Per BPA rule **"Do not summarize numeric columns"** and decision D044 (**force-explicit-measure pattern**), all numeric columns on fact and bridge tables have `SummarizeBy = None`. Users cannot drag a column onto a visual and get an implicit `SUM`, `COUNT`, or `AVERAGE` – they must select a named measure.

**Why:** implicit aggregations have no FormatString, no documentation, no name. They drift silently as schemas evolve. Forcing explicit measures keeps the semantic layer honest and visible in the Fields pane.

**Scope – 33 columns (commit `9679a4d`):**
- `v_rfm_for_bi` (12): Recency Days, Order Count, Total Spend, Total Profit, Margin %, Avg Order Value, Total Units, Avg Products per Order, R/F/M/Health Scores
- `dim_Date` (6): Year, Month, Week of Year, Day, Day Number, Year-Month-Number
- `sales_curated` (9): Order Discount %, Basket Item Count, Order Value, Order Cost, Order Profit, Order Margin %, Total Units, Distinct Products, Source Month
- `v_items_for_bi` (4): Quantity, Line Net Amount, Line Profit, Line Margin %
- `dim_SegmentActions` + `dim_KPI_Selector` (2): SortOrder

**Batch script:** `tools/format_summarize_by_batch.csx` (explicit `(table, column)` targets list – no pattern matching, per audit precision). Uses `KeyValuePair<string,string>` for TE2 Roslyn pre-C# 7.0 compatibility. BPA delta: 28 → 0 violations.

### Foreign Key Visibility (F007)

Per BPA rule **"Hide foreign keys"** and Kimball / SQLBI defensive star schema UX (Russo + Ferrari, *Definitive Guide to DAX*; Kimball, *Data Warehouse Toolkit*), foreign-key columns are hidden in fact and bridge tables, visible only in the canonical dimension.

**Why (three rationales):**
1. **Eliminate duplicate field options** – `Customer ID` exists in `sales_curated`, `v_items_for_bi`, `v_rfm_for_bi`, AND `v_dim_customers_std`. Without hide, user sees 4 instances in Fields pane. After hide: one canonical `Customer ID` from the dimension.
2. **Enforce correct filter propagation** – in a star schema, filters flow from dimensions to facts. Dragging an FK from a fact table creates one-table-only filter context (no cross-fact propagation). Hide forces use of the dim column → correct propagation across `sales_curated` ↔ `v_items_for_bi` ↔ `v_rfm_for_bi`.
3. **Prevent implicit COUNT measures** – FK columns are often Int/Text/DateTime. Pairs with F006 `SummarizeBy=None` and D044 force-explicit-measure pattern to fully block implicit aggregations.

**Hidden – 10 FK cols (commit `0491ed0`):**
- `v_dim_customers_std[Customer ID]` (PK in dim, also FK to itself via auto-detected reflexive – hidden for consistency)
- `v_rfm_for_bi[Last Order Date]` (FK to dim_Date)
- `v_rfm_for_bi[Segment]` (FK to dim_SegmentActions / dim_SegmentOrder)
- `sales_curated[Order ID]` (degenerate dim – never used in viz, just FK to line items)
- `sales_curated[Customer ID]`, `[Order Date]`
- `v_items_for_bi[Order ID]`, `[Product ID]`, `[Customer ID]`
- `dim_SegmentOrder[Segment]` (FK to dim_SegmentActions in bridge relationship)

**Documented exception – D028 dual-grain customer satellite:** `v_rfm_for_bi` is a customer-grain analytic satellite over `v_dim_customers_std`. Its non-FK columns (R/F/M/Health Scores, Recency Days, Order Count, etc.) remain visible because they ARE the analytic payload – used directly in slicers, the Field Parameter on Page 2, and segment-profile visuals. Only the FKs on `v_rfm_for_bi` (`Last Order Date`, `Segment`, plus the `Customer ID` relationship column) are hidden.

**What does NOT change after F007:**
- Relationships remain functional – engine knows FKs even when hidden
- Existing measures unaffected – explicit DAX references columns regardless of Hidden flag
- Storage / query performance unchanged – Hidden is UI-only

### Hidden Fact Columns (F004, D043)

Per audit decision D043, four fact-source columns are hidden to prevent users from bypassing canonical measures (commit `56eba2c`):
- `sales_curated[Order Value]`, `[Order Profit]`
- `v_items_for_bi[Line Net Amount]`, `[Line Profit]`

These remain accessible via `[Total Revenue]`, `[Total Profit]`, `[Line Revenue]`, `[Line Profit]` measures (which reference the columns explicitly in DAX). BPA "Hide fact table columns" rule still shows **8 remaining flags – all intentional exposures** used in Field Parameters, slicers, and visualizations: `v_rfm_for_bi[Recency Days]`, `[Order Count]`, `[Total Spend]`, `[R Score]`, `[F Score]`, `[M Score]`, `[Health Score]`, and `sales_curated[Source Month]`.

---

## Folder: 01 – Core KPIs

| # | Measure | Formula | Format | Pages |
|---|---|---|---|---|
| 1 | Total Revenue | `SUM(sales_curated[Order Value])` | € Currency (€ DE), 2dp, display Millions | 1, 2, 3, 4 |
| 2 | Total Customers | `CALCULATE(DISTINCTCOUNT(dim_Customer[Customer ID]), NOT ISBLANK(dim_Customer[Order Count]))` | # 0dp | 1, 2 |
| 3 | Total Orders | `SUM(dim_Customer[Order Count])` | # 0dp | 1 |
| 4 | Avg Order Value | `DIVIDE([Total Revenue], [Total Orders], 0)` | € Currency, 2dp | 1 |
| 5 | Avg Customer LTV | `DIVIDE([Total Revenue], [Total Customers], 0)` | € Currency, 0dp | 1 |
| 6 | Avg Recency Days | `AVERAGE(dim_Customer[Recency Days])` | Custom `#,##0 "days"` | 1, 2 |
| 7 | Avg Frequency | `AVERAGE(dim_Customer[Order Count])` | Dec 1dp | 2 |
| 8 | Avg Monetary | `AVERAGE(dim_Customer[Total Spend])` | € Currency, 2dp | 2 |
| 25 | Distinct Orders | `DISTINCTCOUNT(sales_curated[Order ID])` | # 0dp | 3 |
| 26 | Total Profit | `SUM(sales_curated[Order Profit])` | € Currency (€ DE), 2dp, display Millions | 1, 3, 4 |
| 27 | Profit Margin % | `DIVIDE([Total Profit], [Total Revenue], 0)` | % 2dp | 1, 3 |
| **30** | **Total Products (v6)** | `DISTINCTCOUNT(dim_Product[Product ID])` | # 0dp | 3 |
| **31** | **Total Brands (v6)** | `DISTINCTCOUNT(dim_Product[Brand])` | # 0dp | 3 |
| **32** | **Top Brand Revenue (v6)** | `MAXX(VALUES(dim_Product[Brand]), [Line Revenue])` | € Currency, display Millions | 3 |
| **33** | **Top Brand Name (v6)** | VAR pattern – see formula block below | Text | 3 |
| **34** | **Avg Brand Margin % (v6)** | `AVERAGEX(VALUES(dim_Product[Brand]), [Line Margin %])` | % 2dp | 3 |
| **35** | **Top Category Revenue (v6)** | `MAXX(VALUES(dim_Product[Product Category]), [Line Revenue])` | € Currency, display Millions | 3 |
| **36** | **Top Category Name (v6)** | VAR pattern – see formula block below | Text | 3 |

**Weighted margin principle (R008):** `Profit Margin %` uses `SUM(profit) / SUM(revenue)`, never `AVERAGE(margin_pct)`. Arithmetic mean of percentages misrepresents aggregate when orders have different sizes.

**Equal-weight benchmark (R025, NEW v6):** `Avg Brand Margin %` uses `AVERAGEX` over brands – equal-weight semantic for benchmarking, NOT P&L. Returns 59.94% vs `Profit Margin %` 59.78% (revenue-weighted) – the two now sit close but remain distinct semantics. Both legitimate, qualifying labels mandatory in UI ("Average Brand Margin", never "Margin").

**Fact-grain principle (R026 + R028 dual-grain naming):** measures #1 (Total Revenue) and #26 (Total Profit) refactored to source from `sales_curated` (order-grain fact table). Dimensional views serve as drill-down axes/legends only.

### Top Brand Name / Top Category Name – full formula

```dax
Top Brand Name =
VAR TopBrand =
    TOPN (
        1,
        VALUES ( dim_Product[Brand] ),
        [Line Revenue], DESC,
        dim_Product[Brand], ASC
    )
RETURN
    MAXX (
        TopBrand,
        dim_Product[Brand]
    )

Top Category Name =
VAR TopCategory =
    TOPN (
        1,
        VALUES ( dim_Product[Product Category] ),
        [Line Revenue], DESC,
        dim_Product[Product Category], ASC
    )
RETURN
    MAXX (
        TopCategory,
        dim_Product[Product Category]
    )
```

**Edge case:** ties in revenue resolve alphabetically first (TOPN ASC tiebreak on the name column). Acceptable for KPI cards – display only.

---

## Folder: 02 – RFM Scores

| # | Measure | Formula | Format | Pages |
|---|---|---|---|---|
| 9 | Avg R Score | `AVERAGE(dim_Customer[R Score])` | Dec 1dp | 2, 6 |
| 10 | Avg F Score | `AVERAGE(dim_Customer[F Score])` | Dec 1dp | 2, 6 |
| 11 | Avg M Score | `AVERAGE(dim_Customer[M Score])` | Dec 1dp | 2, 6 |
| 12 | Avg Health Score | `AVERAGE(dim_Customer[Health Score])` | Dec 1dp | 1, 2, 4 |

---

## Folder: 03 – Segment Analysis

| # | Measure | Format | Pages |
|---|---|---|---|
| 13 | Segment % of Total | % 1dp | 1, 2 |
| 14 | Revenue % of Total | % 1dp | 2 |
| 15 | Revenue at Risk | € 0dp | 1, 4 |

```dax
Segment % of Total =
VAR SegmentCount =
    CALCULATE(
        COUNTROWS(dim_Customer),
        NOT ISBLANK(dim_Customer[Order Count])
    )
VAR TotalCount =
    CALCULATE(
        COUNTROWS(dim_Customer),
        ALL(dim_Customer),
        NOT ISBLANK(dim_Customer[Order Count])
    )
RETURN
DIVIDE(SegmentCount, TotalCount, 0)
```

```dax
Revenue % of Total =
VAR SegmentRevenue = SUM(dim_Customer[Total Spend])
VAR TotalRevenue =
    CALCULATE(
        SUM(dim_Customer[Total Spend]),
        ALL(dim_Customer)
    )
RETURN
DIVIDE(SegmentRevenue, TotalRevenue, 0)
```

```dax
Revenue at Risk =
CALCULATE(
    SUM(dim_Customer[Total Spend]),
    dim_Customer[Segment] IN {"At Risk", "Hibernating"}
)
```

---

## Folder: 04 – Time Intelligence (Recency Buckets)

| # | Measure | Format | Pages |
|---|---|---|---|
| 16 | Revenue Active (0–90d) | € 0dp | 4 |
| 17 | Revenue Cooling (91–180d) | € 0dp | 4 |
| 18 | Revenue Dormant (180d+) | € 0dp | 4 |

```dax
Revenue Active =
CALCULATE(
    SUM(dim_Customer[Total Spend]),
    dim_Customer[Recency Days] <= 90
)

Revenue Cooling =
CALCULATE(
    SUM(dim_Customer[Total Spend]),
    dim_Customer[Recency Days] > 90
        && dim_Customer[Recency Days] <= 180
)

Revenue Dormant =
CALCULATE(
    SUM(dim_Customer[Total Spend]),
    dim_Customer[Recency Days] > 180
)
```

---

## Folder: 05 – Dynamic & What-If

| # | Measure | Format | Pages |
|---|---|---|---|
| 19 | What-If Revenue Impact | € 0dp | 4 |
| 20 | Dynamic KPI Selector | varies | 2 |

```dax
What-If Revenue Impact =
VAR AtRiskRev =
    CALCULATE(
        SUM(dim_Customer[Total Spend]),
        dim_Customer[Segment] IN {"At Risk", "Hibernating"}
    )
VAR Rate =
    SELECTEDVALUE('Reactivation Rate'[Reactivation Rate Value], 10) / 100
RETURN
AtRiskRev * Rate
```

```dax
Dynamic KPI Selector =
VAR Selected =
    SELECTEDVALUE(dim_KPI_Selector[KPI Name], "Total Revenue")
RETURN
SWITCH(
    Selected,
    "Total Revenue",    [Total Revenue],
    "Total Customers",  [Total Customers],
    "Avg Order Value",  [Avg Order Value],
    "Avg Recency",      [Avg Recency Days],
    "Revenue at Risk",  [Revenue at Risk],
    [Total Revenue]
)
```

---

## Folder: 06 – Formatting & Regional

| # | Measure | Purpose | Format | Pages |
|---|---|---|---|---|
| 21 | Health Indicator | Status text from health_score | Text | 1, 6 |
| 22 | ARPU by Country | Revenue per customer (context-aware) | € 2dp | 5 |
| 23 | Country Revenue Share | Country share of total revenue | % 1dp | 5 |
| 24 | Segment Color | Hex color per segment (SWITCH) – **USE ONLY IF dim_SegmentOrder[SegmentColor] column is not used for conditional formatting** | Hex text | All |
| 28 | Monthly Trend Title | Dynamic line chart title with live month count | Text | 1 |
| 29 | **Subtitle Page 1** (renamed from Executive Summary Subtitle, v6) | Dynamic Page 1 subtitle with live month count | Text | 1 |
| **37** | **Subtitle Page 2 (v6)** | Dynamic Page 2 subtitle with live segment count | Text | 2 |
| **38** | **Subtitle Page 3 (v6)** | Dynamic Page 3 subtitle with product + brand counts | Text | 3 |

```dax
Health Indicator =
VAR Score = AVERAGE(dim_Customer[Health Score])
RETURN
SWITCH(
    TRUE(),
    Score >= 11, "● Healthy",
    Score >= 7,  "◐ Monitor",
    "○ Critical"
)
```

```dax
ARPU by Country =
DIVIDE(
    SUM(dim_Customer[Total Spend]),
    CALCULATE(
        COUNTROWS(dim_Customer),
        NOT ISBLANK(dim_Customer[Order Count])
    ),
    0
)
```

```dax
Country Revenue Share =
DIVIDE(
    SUM(dim_Customer[Total Spend]),
    CALCULATE(
        SUM(dim_Customer[Total Spend]),
        ALL(dim_Customer)
    ),
    0
)
```

```dax
Segment Color =
SWITCH(
    SELECTEDVALUE(dim_Customer[Segment]),
    "Champions",            "#4A7AA0",
    "Loyal Customers",      "#7BA8B8",
    "Potential Loyalists",  "#8FA87E",
    "Recent Customers",     "#D4A762",
    "At Risk",              "#A05A55",
    "Hibernating",          "#A5A29A",
    "#A5A29A"
)
```

**Design decision – Segment Color:** dim_SegmentOrder has a `SegmentColor` column with the same hex values. For conditional formatting, prefer the column (more performant). The Segment Color measure exists as a fallback for visuals that require a measure for color rules. Do not use both simultaneously on the same visual.

```dax
Monthly Trend Title =
"Monthly Revenue Trend (" &
COUNTROWS(v_monthly_revenue) &
" Complete Months)"
```

**Design decision – dynamic chart title:** Line chart on Page 1 uses Field Value → `[Monthly Trend Title]` bound to visual Title via fx. Auto-updates as new months arrive in v_monthly_revenue (which already filters incomplete months via SQL patch in 03_v2). Future-proof: no manual title edits when data extends.

```dax
Subtitle Page 1 =
"Kupferkanne – D2C E-commerce · 9 European markets · Rolling " &
COUNTROWS(v_monthly_revenue) &
" months"
```

```dax
Subtitle Page 2 = 
"RFM profile comparison across " & 
DISTINCTCOUNT(dim_SegmentOrder[Segment]) & 
" segments"
```

```dax
Subtitle Page 3 = 
"Profitability across " & [Total Products] & " products and " & [Total Brands] & " brands"
```

**Design decision – Subtitle Page N convention (D022, R027, NEW v6):** All page subtitles follow `Subtitle Page N` naming convention for consistency across Pages 1-7. All bound via fx → Field value to subtitle text boxes. Subtitle Page 2 was static text in v5; refactored to dynamic measure in v6. Subtitle Page 3 added new for Page 3 build.

---

## Product, brand and category measures (Page 3)

Post-D060 the pre-aggregated views (`v_product_analytics`, `v_product_performance`, `v_brand_profitability`, `v_category_monthly_trend`) were removed from the model. Page 3 product, brand and category figures are now DAX measures (Folder 01), sourced from `dim_Product` as the axis or legend over the line-grain fact `v_items_for_bi` via `[Line Revenue]` and `[Line Margin %]`. See Folder 01 and the Data Model map above for the canonical definitions.

---

## Supporting Tables

### dim_Date – M-code Rolling Calendar

```m
let
    Source = #date(2022, 1, 1),
    EndDate = Date.EndOfMonth(DateTime.Date(DateTime.LocalNow())),
    DayCount = Duration.Days(EndDate - Source) + 1,
    ListOfDates = List.Dates(Source, DayCount, #duration(1, 0, 0, 0)),
    #"Converted to Table" = Table.FromList(ListOfDates, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
    #"Renamed Columns" = Table.RenameColumns(#"Converted to Table",{{"Column1", "Date"}}),
    #"Changed Type" = Table.TransformColumnTypes(#"Renamed Columns",{{"Date", type date}}),
    #"Inserted Year" = Table.AddColumn(#"Changed Type", "Year", each Date.Year([Date]), Int64.Type),
    #"Inserted Month" = Table.AddColumn(#"Inserted Year", "Month", each Date.Month([Date]), Int64.Type),
    #"Inserted Month Name" = Table.AddColumn(#"Inserted Month", "Month Name", each Date.MonthName([Date]), type text),
    #"Inserted Year-Month" = Table.AddColumn(#"Inserted Month Name", "Year-Month", each Date.ToText([Date], "yyyy-MM"), type text),
    #"Inserted Quarter" = Table.AddColumn(#"Inserted Year-Month", "Quarter", each "Q" & Text.From(Date.QuarterOfYear([Date])), type text),
    #"Inserted Week of Year" = Table.AddColumn(#"Inserted Quarter", "Week of Year", each Date.WeekOfYear([Date]), Int64.Type),
    #"Inserted Start of Week" = Table.AddColumn(#"Inserted Week of Year", "Start of Week", each Date.StartOfWeek([Date], Day.Monday), type date),
    #"Inserted Day" = Table.AddColumn(#"Inserted Start of Week", "Day", each Date.Day([Date]), Int64.Type),
    #"Inserted Day Name" = Table.AddColumn(#"Inserted Day", "Day Name", each Date.DayOfWeekName([Date]), type text),
    #"Inserted Day Sort" = Table.AddColumn(#"Inserted Day Name", "Day Sort", each Date.DayOfWeek([Date], Day.Monday) + 1, Int64.Type)
in
    #"Inserted Day Sort"
```

After load: Mark as Date Table (Date column). Sort by Column: Month Name → Month. Sort by Column: Day Name → Day Sort.

### dim_SegmentOrder – DAX DATATABLE

```dax
dim_SegmentOrder =
DATATABLE (
    "Segment", STRING,
    "SortOrder", INTEGER,
    "SegmentColor", STRING,
    {
        { "Champions", 1, "#4A7AA0" },
        { "Loyal Customers", 2, "#7BA8B8" },
        { "Potential Loyalists", 3, "#8FA87E" },
        { "Recent Customers", 4, "#D4A762" },
        { "At Risk", 5, "#A05A55" },
        { "Hibernating", 6, "#A5A29A" }
    }
)
```

After load: Sort by Column: Segment → SortOrder. Relationship: v_rfm_for_bi[segment] → dim_SegmentOrder[Segment] (Many:1).

**Note (F028, 2026-05-22):** DATATABLE expression reformatted per SQLBI / daxformatter.com gold standard – spaces inside parens, padded braces. Documented in audit findings.

**Note:** ActionPriority is NOT included here. The `action` column already exists in v_rfm_for_bi (from SQL: `recommended_action AS action`). No duplication needed.

### dim_KPI_Selector – Enter Data

5 rows, 1 column (`KPI Name`): Total Revenue, Total Customers, Avg Order Value, Avg Recency, Revenue at Risk. **Disconnected** – no relationship to any table.

### Reactivation Rate – What-If Parameter

Modeling → New Parameter → Name: Reactivation Rate, Min: 0, Max: 50, Increment: 5, Default: 10.

---

## Relationships

The authoritative relationship list is the **Active relationships (5)** table in the Data Model section above (post-D060: 5 active, all M:1 single-direction, 0 bidirectional). It is not duplicated here, to avoid drift.

**Disconnected / standalone:** `dim_KPI_Selector` is a disconnected slicer (no relationship). Pre-aggregated views (`v_monthly_revenue`, `v_brand_profitability`, etc.) have no relationships – standalone tables used directly on specific pages.

### Fact-to-fact joins: explicitly NOT used (F008, v7)

After F008 (commit `40f57f3`), the auto-detected inactive relationship `v_items_for_bi[Order ID] → sales_curated[Order ID]` was removed. The model now has **zero inactive relationships**. The deliberate design choice – consistent with Kimball star-schema discipline and the dual-grain D026 architecture – is that fact tables never join directly to other fact tables. Instead:

- **Cross-fact filter propagation** flows through shared dimensions (`dim_Customer`, `dim_Product`, `dim_Date`)
- **Order-grain ↔ line-grain reconciliation** is done via measure math, not a relationship. The `[Grain Reconciliation]` measure computes `[Total Revenue] − [Line Revenue]` and is invariant at zero. If it ever drifts from zero, the dimension-mediated join has broken – that's the signal, not a relationship line in the model
- **USERELATIONSHIP**: no DAX expression in the model uses `USERELATIONSHIP()` to activate a fact-to-fact join. The removed `Order ID` relationship had zero callers, confirming the inactive-and-unused pattern that BPA flags

**BPA delta:** "Inactive relationships that are never activated" rule 1 → 0 violations.

---

## Total: 29 measures in 6 display folders + 1 Field Parameter. No orphans. No redundant calculations.

*(Note: total measure count is the v3-era tally. Actual v6 inventory is 36 base measures + 3 Subtitle measures + 1 Field Parameter – see Changelog. v7 batch did not change measure inventory; all changes were metadata-only.)*

---

## Field Parameter: RFM Score Selector (Page 2)

**Created via:** Modeling → New parameter → Fields

**Fields included (in order):**
- `v_rfm_for_bi[R Score]`
- `v_rfm_for_bi[F Score]`
- `v_rfm_for_bi[M Score]`

**Auto-generates:**
- Parameter table `RFM Score Selector` (disconnected)
- Page 2 slicer (Tile style)

**Usage:**
- Page 2 Column chart X-axis: `RFM Score Selector` (parameter column)
- Y-axis: `[Total Customers]`
- Slicer toggles between R / F / M distributions without DAX

**Decision rationale:** Field Parameters chosen over custom DAX SWITCH measure + helper dim table because:
- Native Power BI feature (2022+), zero maintenance
- Cleaner than 3 separate charts + bookmarks
- Row-context issues make SELECTEDVALUE-based approaches return BLANK on score axis

**v7 note (F007):** the three score columns referenced by this Field Parameter (`R Score`, `F Score`, `M Score`) are explicitly NOT in scope for F007 FK-hide. Per D028 dual-grain customer satellite exception, they remain visible because they ARE the analytic payload of `v_rfm_for_bi`, not foreign keys.

---

## Changelog

### v7 (2026-05-24)
- **v1.0.1 BPA-batch sync per R041** (atomic invariant: BPA + docs same session). All four findings landed across two sessions (2026-05-22, 2026-05-24), all in `main` at HEAD `40f57f3`
- **F003 (commit `43e4241`):** 32 measures normalized FormatStrings per SQLBI gold standard. New **Format String Standards** section documents conventions (currency, percent, count, decimal, date, text). Batch script `tools/format_string_batch.csx` introduced per R043 hygiene (dryRun + manual-override + `INFO.VIEW.*` pre-flight)
- **F004 (commit `56eba2c`):** 4 critical fact-source columns hidden (`sales_curated[Order Value]/[Order Profit]`, `v_items_for_bi[Line Net Amount]/[Line Profit]`). Documented in new **Hidden Fact Columns** section. BPA "Hide fact table columns" rule retains 8 intentional flags (Recency Days, Order Count, Total Spend, R/F/M/Health Scores, Source Month) – all used in Field Parameters / slicers / visuals
- **F006 (commit `9679a4d`):** 33 columns `SummarizeBy=None` per D044 force-explicit-measure pattern. New **Column Behavior** section explains why implicit aggregations are blocked. Batch script `tools/format_summarize_by_batch.csx` (explicit targets list, KeyValuePair pattern for TE2 Roslyn pre-C# 7.0). BPA delta: 28 → 0
- **F007 (commit `0491ed0`):** 10 FK columns hidden per Kimball / SQLBI defensive star-schema UX. New **Foreign Key Visibility** section with three rationales (eliminate duplicate fields, enforce filter propagation, prevent implicit COUNT). D028 dual-grain customer satellite documented as exception: `v_rfm_for_bi` non-FK analytic columns remain visible. BPA delta: 10 → 0
- **F008 (commit `40f57f3`):** removed auto-detected inactive relationship `v_items_for_bi[Order ID] → sales_curated[Order ID]`. **Relationships** section updated with explicit "fact-to-fact joins NOT used" policy and grain-reconciliation-via-measure-math (Grain Reconciliation invariant = 0). BPA delta: 1 → 0
- **F028 (RESOLVED 2026-05-22):** `dim_SegmentOrder` DATATABLE expression reformatted per SQLBI / daxformatter.com gold standard (spaces inside parens, padded braces). Reflected in the dim_SegmentOrder DAX block above
- **No measure inventory change.** All v1.0.1 batch findings were metadata operations (FormatString / Hidden / SummarizeBy / relationship removal). Folder structure, measure definitions, and counts unchanged from v6. Stale `Total: 29` tally line preserved with a note pointing to actual v6 inventory (36 + 3 Subtitle + Field Parameter)
- **F005 (Float → Fixed Decimal type change) deferred to v1.1** per O1 – type change has measure-recompute and storage-format implications, warrants its own session with full regression suite

### v6 (2026-04-24)
- **sales_curated imported as primary fact table** – order-grain curated table (~169K rows). 3 new relationships to dim_customers, dim_products, dim_Date
- **Measure #1 `Total Revenue` refactored:** `SUM(v_rfm_for_bi[total_spend])` → `SUM(sales_curated[LineNetAmount])`. Resolves Top 15 Products bar chart bug (filter context didn't propagate from product Y-axis to Customer-grain measure)
- **Measure #26 `Total Profit` refactored:** `SUM(v_rfm_for_bi[total_profit])` → `SUM(sales_curated[LineProfit])`
- **+7 Page 3 measures (#30-#36):** Total Products, Total Brands, Top Brand Revenue, Top Brand Name, Avg Brand Margin %, Top Category Revenue, Top Category Name
- **Subtitle Page N convention (D022, R027):** Measure #29 renamed `Executive Summary Subtitle` → `Subtitle Page 1`. Added #37 `Subtitle Page 2` (refactored from static text to dynamic) and #38 `Subtitle Page 3` (new for Page 3 build)
- **Two-tier margin (R025, D023):** `Profit Margin %` (weighted, P&L truth, 59.78%) + `Avg Brand Margin %` (equal-weight, benchmarking, 51.88%). Both legitimate, qualifying labels mandatory
- **Architecture rule R026:** `[Total Revenue]`/`[Total Profit]` measures pull from fact-grain `sales_curated` ONLY. Dimensional views serve as drill-down axes/legends only
- Total measure count: 36 + 3 Subtitle (Pages 1-3) + Field Parameter

### v5 (2026-04-22)
- **Added measure #29** `Executive Summary Subtitle` – dynamic page subtitle bound via fx → Field value on Page 1 subtitle text box
- **Added Field Parameter** `RFM Score Selector` (not a measure – Power BI native feature) for Page 2 R/F/M toggle column chart
- **Removed planned measure** `Selected RFM Score Count` (was in Page 2 workflow v1) – replaced by Field Parameters; row-context issues with SELECTEDVALUE made the DAX approach non-functional
- **Table rename:** all v_rfm_for_bi columns use Title Case with spaces in Power BI (not snake_case): `R Score`, `F Score`, `M Score`, `Recency Days`, etc. Source SQL view uses snake_case; rename happens in Model view

### v4 (2026-04-22)
- **Palette C Muted Earth recalibration** – all 6 segment colors changed:
  - Champions `#2563EB` → `#4A7AA0` (muted blue)
  - Loyal Customers `#0891B2` → `#7BA8B8` (light teal)
  - Potential Loyalists `#059669` → `#8FA87E` (sage green)
  - Recent Customers `#D97706` → `#D4A762` (muted ochre)
  - At Risk `#A32638` → `#A05A55` (dimmed terracotta)
  - Hibernating `#6B7280` → `#A5A29A` (warm stone gray)
- Applied in: Measure #24 `Segment Color` SWITCH + `dim_SegmentOrder` DATATABLE
- Rationale: magazine/editorial feel (Economist/FT style), maximum restraint, no color competes for attention. Ryszard selected from 3 palette proposals based on McKinsey 7S + donut inspirations.

### v3 (2026-04-22)
- **Added 4 measures** (total 24 → 28):
  - #25 `Distinct Orders` (folder 01) – `DISTINCTCOUNT(v_product_analytics[OrderID])`, for product-filtered order counts on Page 3
  - #26 `Total Profit` (folder 01) – `SUM(v_rfm_for_bi[total_profit])`, for Page 1 KPI card
  - #27 `Profit Margin %` (folder 01) – `DIVIDE([Total Profit], [Total Revenue], 0)`, weighted margin principle
  - #28 `Monthly Trend Title` (folder 06) – dynamic DAX string for auto-updating line chart title
- **Currency locale:** all EUR measures switched from default `$` to `€ German (Germany)`
- **Avg Recency Days format:** changed from `# 0dp` to custom `#,##0 "days"` for inline suffix
- **Validation:** Total Profit = €5.10M, Profit Margin % = 59.78% (weighted avg pulled up by high-spend Champions at 60.9%)

### v2 (2026-04-22)
- Palette recalibration: "At Risk" segment color `#DC2626` → `#A32638` in measure #24 and dim_SegmentOrder DATATABLE
