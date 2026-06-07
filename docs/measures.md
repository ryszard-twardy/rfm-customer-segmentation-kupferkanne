# DAX Measures Reference
## Kupferkanne – 47 DAX Measures (46 in 6 Display Folders + 1 What-If Parameter Measure)
### Author: Ryszard Twardy
### v7 (2026-05-24) – synced with v1.0.1 BPA batch (F003 format strings, F004 hide fact cols, F006 SummarizeBy=None, F007 hide FKs, F008 remove inactive relationship) per R041 atomic invariant

> Source of truth for all DAX measures. Every table and column name verified against BigQuery SQL scripts (03_rfm_pipeline, 05_analytics_marts). **Since dual-grain D026 (2026-05-07)**, Power BI imports `sales_curated` (order-grain fact table from script 03_rfm_pipeline) as the primary fact source. `dim_Customer` (the BI-facing customer dimension) carries the customer-grain analytics after the D060 single-direction refactor. **As of v7 (v1.0.1 BPA batch, 2026-05-24)**, model-wide hygiene policies on FormatString, SummarizeBy, Hidden, and Relationships are documented in the **Model Hygiene** section below.

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

The conventions below are model-wide metadata policies established during the v1.0.1 BPA batch (sessions 2026-05-22 and 2026-05-24, commits `43e4241`, `56eba2c`, `9679a4d`, `0491ed0`, `40f57f3`) and carried forward through the D060 single-direction refactor. They change no measure expressions and no display-folder structure. Every measure and column in this document conforms to them.

### Format String Standards (F003, D044)

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

**Coverage:** 34 of 47 measures carry an explicit `FormatString`. The 13 without: 12 intentional text measures + `[Dynamic KPI Selector]` (format inherited at evaluation via `SWITCH`). Three special-case formats preserved:
- `[Avg Health Score]` → `0.0 "/ 15"` (score-out-of-15 semantic)
- `[Reactivation Rate Value]` → `0` (integer percentage points, not a ratio)
- `[Dynamic KPI Selector]` → format inherited via `SWITCH` from the selected measure

**Batch script:** `tools/format_string_batch.csx` (R043 hygiene: `dryRun=true` default, explicit manual-override helper, BPA pre-flight via `INFO.VIEW.MEASURES()` introspection). Reference implementation for future TE2 pattern-matching batches. The batch reduced the BPA "Provide format string for measures" rule from 45 flags to 13; all 13 remaining are intentional (12 text + 1 `SWITCH`-format).

### Column Behavior: SummarizeBy = None (F006)

Per BPA rule **"Do not summarize numeric columns"** and the force-explicit-measure pattern (audit finding F006, issue #4), every non-additive numeric column on the fact and dimension tables has `SummarizeBy = None`. Users cannot drag a column onto a visual and get an implicit `SUM`, `COUNT`, or `AVERAGE` – they must select a named measure.

**Why:** implicit aggregations have no `FormatString`, no documentation, no name. They drift silently as schemas evolve. Forcing explicit measures keeps the semantic layer honest and visible in the Fields pane.

**Scope – 32 columns (commit `9679a4d`); authoritative target list in `tools/format_summarize_by_batch.csx`:**

| Table | Cols | Columns |
|---|---|---|
| `dim_Customer` | 11 | Recency Days, Order Count, Total Spend, Total Profit, Margin %, Total Units, Avg Products per Order, R Score, F Score, M Score, Health Score |
| `dim_Date` | 6 | Year, Month, Week of Year, Day, Day Number, Year-Month-Number |
| `dim_Segment` | 1 | SortOrder |
| `sales_curated` | 9 | Order Discount %, Basket Item Count, Order Value, Order Cost, Order Profit, Order Margin %, Total Units, Distinct Products, Source Month |
| `v_items_for_bi` | 4 | Quantity, Line Net Amount, Line Profit, Line Margin % |
| `dim_KPI_Selector` | 1 | SortOrder |

**Batch script:** `tools/format_summarize_by_batch.csx` (explicit `(table, column)` targets list – no pattern matching, per audit precision). Uses `KeyValuePair<string,string>` for TE2 Roslyn pre-C# 7.0 compatibility. BPA delta: 28 → 0 violations.

`SummarizeBy = None` and `isHidden` are independent properties – a column can be `SummarizeBy = None` and still visible (`dim_Date[Year]`), or both `SummarizeBy = None` and hidden (`dim_Customer[Total Spend]`).

### Foreign Key & Surrogate Key Visibility (F007)

Per BPA rule **"Hide foreign keys"** and Kimball / SQLBI defensive star-schema UX (Russo + Ferrari, *Definitive Guide to DAX*; Kimball, *Data Warehouse Toolkit*), keys that exist only to wire relationships are hidden; keys that double as user-facing attributes stay visible on their dimension.

**Why (three rationales):**
1. **Remove plumbing from the Fields pane** – `Customer ID` and `Product ID` are surrogate keys users never filter on directly (they filter by `Full Name`, `Country`, `Brand`, `Product Category`). Both are hidden on every table that carries them, fact and dimension alike. Keys that are themselves attributes – `Order Date` → `dim_Date[Date]`, `Segment` → `dim_Segment[Segment]` – stay visible so users can use them.
2. **Enforce correct filter propagation** – in a single-direction star, filters flow from dimensions to facts. Dragging an FK from a fact creates a one-table-only filter context. Hiding the fact-side FK forces use of the dimension column, so a `dim_Customer` filter propagates to both `sales_curated` and `v_items_for_bi`.
3. **Block implicit COUNT measures** – FK columns are Int/Text/DateTime. Hiding them pairs with F006 `SummarizeBy = None` and the force-explicit-measure pattern to fully block implicit aggregations.

**Hidden – relationship & degenerate keys (commit `0491ed0`, retopologised in D060):**

| Table | Hidden key column(s) | Class |
|---|---|---|
| `dim_Customer` | `Customer ID` | PK / target of two fact FKs |
| `dim_Product` | `Product ID` | PK / target of `v_items_for_bi` FK |
| `sales_curated` | `Customer ID`, `Order Date` | FK → `dim_Customer`, `dim_Date` |
| `sales_curated` | `Order ID` | degenerate dimension (no relationship) |
| `v_items_for_bi` | `Customer ID`, `Product ID` | FK → `dim_Customer`, `dim_Product` |
| `v_items_for_bi` | `Order ID` | degenerate dimension (inactive relationship removed, F008) |

Visible keys: `dim_Date[Date]` and `dim_Segment[Segment]` – user-facing attributes, not pure plumbing.

**RFM analytic payload on `dim_Customer` (D060):** the D060 refactor folded the former `v_rfm_for_bi` satellite into `dim_Customer`. Its scoring columns – `R Score`, `F Score`, `M Score`, `Health Score`, `Recency Days`, `Order Count`, `Total Spend` – are hidden and surfaced through measures (`[Avg R Score]`, `[Avg Health Score]`, …) and referenced by name in the Page-2 Field Parameter (field parameters resolve hidden source columns). Pre-D060 these stayed visible under the D028 dual-grain satellite exception; after the merge that exception no longer applies. Descriptive attributes (`Full Name`, `Country`, `Last Order Date`, `RFM Cell`, `Action`) remain visible.

**What does NOT change after F007:**
- Relationships remain functional – the engine resolves keys even when hidden
- Existing measures unaffected – explicit DAX references columns regardless of `isHidden`
- Storage / query performance unchanged – `isHidden` is UI-only

### Hidden Fact Columns (F004, D043)

Per audit decision D043, four fact-source value columns are hidden so users reach them only through the canonical measures (commit `56eba2c`):
- `sales_curated[Order Value]`, `[Order Profit]`
- `v_items_for_bi[Line Net Amount]`, `[Line Profit]`

These remain accessible via `[Total Revenue]`, `[Total Profit]`, `[Line Revenue]`, `[Line Profit]`, which reference the columns explicitly in DAX.

**Total hidden across the model: 20 columns** – 8 relationship/degenerate keys, 4 fact-source value columns, 7 RFM payload columns on `dim_Customer`, 1 sort helper (`dim_Segment[SortOrder]`).

---

## Folder: 01 – Core KPIs

| Measure | Formula | Format | Pages |
|---|---|---|---|
| Total Revenue | `SUM(sales_curated[Order Value])` | € Currency (€ DE), 2dp, display Millions | 1, 2, 3, 4 |
| Total Customers | `CALCULATE(DISTINCTCOUNT(dim_Customer[Customer ID]), NOT ISBLANK(dim_Customer[Order Count]))` | # 0dp | 1, 2 |
| Total Orders | `SUM(dim_Customer[Order Count])` | # 0dp | 1 |
| Avg Order Value | `DIVIDE([Total Revenue], [Total Orders], 0)` | € Currency, 2dp | 1 |
| Avg Customer LTV | `DIVIDE([Total Revenue], [Total Customers], 0)` | € Currency, 0dp | 1 |
| Avg Recency Days | `AVERAGE(dim_Customer[Recency Days])` | Custom `#,##0 "days"` | 1, 2 |
| Avg Frequency | `AVERAGE(dim_Customer[Order Count])` | Dec 1dp | 2 |
| Avg Monetary | `AVERAGE(dim_Customer[Total Spend])` | € Currency, 2dp | 2 |
| Distinct Orders | `DISTINCTCOUNT(sales_curated[Order ID])` | # 0dp | 3 |
| Total Profit | `SUM(sales_curated[Order Profit])` | € Currency (€ DE), 2dp, display Millions | 1, 3, 4 |
| Profit Margin % | `DIVIDE([Total Profit], [Total Revenue], 0)` | % 2dp | 1, 3 |
| Line Revenue | `SUM(v_items_for_bi[Line Net Amount])` | € Currency, 2dp | – |
| Line Profit | `SUM(v_items_for_bi[Line Profit])` | € Currency, 2dp | – |
| Line Margin % | `DIVIDE([Line Profit], [Line Revenue], 0)` | % 2dp | – |
| Grain Reconciliation | `[Total Revenue] - [Line Revenue]` | € Currency, 2dp | – |
| Total Products | `DISTINCTCOUNT(dim_Product[Product ID])` | # 0dp | 3 |
| Total Brands | `DISTINCTCOUNT(dim_Product[Brand])` | # 0dp | 3 |
| Top Brand Revenue | `MAXX(VALUES(dim_Product[Brand]), [Line Revenue])` | € Currency, display Millions | 3 |
| Top Brand Name | VAR pattern – see formula block below | Text | 3 |
| Avg Brand Margin % | `AVERAGEX(VALUES(dim_Product[Brand]), [Line Margin %])` | % 2dp | 3 |
| Top Category Revenue | `MAXX(VALUES(dim_Product[Product Category]), [Line Revenue])` | € Currency, display Millions | 3 |
| Top Category Name | VAR pattern – see formula block below | Text | 3 |

**Dependency / diagnostic measures (Pages = –):** `Line Revenue`, `Line Profit`, `Line Margin %` are line-grain building blocks consumed by the brand/category measures (`[Top Brand Revenue]`, `[Avg Brand Margin %]`, …); `Grain Reconciliation` (`[Total Revenue] - [Line Revenue]`) is a QA invariant (expected 0). None are bound to a visual directly.

**Weighted margin principle (R008):** `Profit Margin %` uses `SUM(profit) / SUM(revenue)`, never `AVERAGE(margin_pct)`. Arithmetic mean of percentages misrepresents aggregate when orders have different sizes.

**Equal-weight benchmark (R025, NEW v6):** `Avg Brand Margin %` uses `AVERAGEX` over brands – equal-weight semantic for benchmarking, NOT P&L. Returns 59.94% vs `Profit Margin %` 59.78% (revenue-weighted) – the two now sit close but remain distinct semantics. Both legitimate, qualifying labels mandatory in UI ("Average Brand Margin", never "Margin").

**Fact-grain principle (R026 + R028 dual-grain naming):** measures `[Total Revenue]` and `[Total Profit]` refactored to source from `sales_curated` (order-grain fact table). Dimensional views serve as drill-down axes/legends only.

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

| Measure | Formula | Format | Pages |
|---|---|---|---|
| Avg R Score | `AVERAGE(dim_Customer[R Score])` | Dec 1dp | 2, 6 |
| Avg F Score | `AVERAGE(dim_Customer[F Score])` | Dec 1dp | 2, 6 |
| Avg M Score | `AVERAGE(dim_Customer[M Score])` | Dec 1dp | 2, 6 |
| Avg Health Score | `AVERAGE(dim_Customer[Health Score])` | Dec 1dp | 1, 2, 4 |

---

## Folder: 03 – Segment Analysis

| Measure | Format | Pages |
|---|---|---|
| Segment % of Total | % 1dp | 1, 2 |
| Revenue % of Total | % 1dp | 2 |
| Revenue at Risk | € 0dp | 1, 4 |

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

| Measure | Format | Pages |
|---|---|---|
| Revenue Active (0–90d) | € 0dp | 4 |
| Revenue Cooling (91–180d) | € 0dp | 4 |
| Revenue Dormant (180d+) | € 0dp | 4 |

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

| Measure | Format | Pages |
|---|---|---|
| What-If Revenue Impact | € 0dp | 4 |
| Dynamic KPI Selector | varies | 2 |
| Dynamic KPI Label | Text | 2 |

```dax
What-If Revenue Impact =
VAR AtRiskRev =
    CALCULATE(
        SUM(dim_Customer[Total Spend]),
        dim_Customer[Segment] IN {"At Risk", "Hibernating"}
    )
VAR Rate =
    SELECTEDVALUE('Reactivation Rate'[Reactivation Rate], 10) / 100
RETURN
AtRiskRev * Rate
```

```dax
Dynamic KPI Selector =
VAR Selected =
    SELECTEDVALUE(dim_KPI_Selector[KPI], "Total Revenue")
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

**What-If parameter measure (no display folder):** `Reactivation Rate Value` = `SELECTEDVALUE('Reactivation Rate'[Reactivation Rate], 10)` (format `0`) lives on the `Reactivation Rate` what-if parameter table, not in a display folder. It is the auto-generated parameter value; `[What-If Revenue Impact]` consumes the parameter. Not bound to any visual.

---

## Folder: 06 – Formatting & Regional

| Measure | Purpose | Format | Pages |
|---|---|---|---|
| Health Indicator | Status text from health_score | Text | 1, 6 |
| ARPU by Country | Revenue per customer (context-aware) | € 2dp | 5 |
| Country Revenue Share | Country share of total revenue | % 1dp | 5 |
| Segment Color | Hex color per segment (SWITCH) – USE ONLY IF dim_Segment[SegmentColor] column is not used for conditional formatting | Hex text | All |
| Revenue Trend Chart Title | Dynamic line chart title with live month count | Text | 1 |
| Subtitle Page 1 | Dynamic Page 1 subtitle with live month count | Text | 1 |
| Subtitle Page 2 | Dynamic Page 2 subtitle with live segment count | Text | 2 |
| Subtitle Page 3 | Dynamic Page 3 subtitle with product + brand counts | Text | 3 |
| R Label | Static axis caption for the RFM Field Parameter | Text | 2 |
| M Label | Static axis caption for the RFM Field Parameter | Text | 2 |
| F Label | Static axis caption for the RFM Field Parameter | Text | 2 |

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

**Design decision – Segment Color:** dim_Segment has a `SegmentColor` column with the same hex values. For conditional formatting, prefer the column (more performant). The Segment Color measure exists as a fallback for visuals that require a measure for color rules. Do not use both simultaneously on the same visual.

```dax
Revenue Trend Chart Title =
"Weekly Revenue Trend Across "
    & DISTINCTCOUNT ( sales_curated[Source Month] )
    & " Months"
```

**Design decision – dynamic chart title:** the Page 1 revenue trend chart binds its Title to `[Revenue Trend Chart Title]` via fx (Field Value). The month count comes from `DISTINCTCOUNT ( sales_curated[Source Month] )`, so the title auto-updates as new months arrive – no manual edits when data extends.

```dax
Subtitle Page 1 =
"Kupferkanne – D2C E-commerce · 9 European markets · Rolling " &
DISTINCTCOUNT ( sales_curated[Source Month] ) &
" months"
```

```dax
Subtitle Page 2 = 
"RFM profile comparison across " & 
DISTINCTCOUNT(dim_Segment[Segment]) & 
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

### dim_Segment – DAX DATATABLE

```dax
dim_Segment =
DATATABLE (
    "Segment", STRING,
    "Email Cadence", STRING,
    "Loyalty Tier", STRING,
    "Discount Approach", STRING,
    "Budget Allocation", STRING,
    "SortOrder", INTEGER,
    "SegmentColor", STRING,
    {
        { "Champions", "Monthly newsletter", "VIP Tier", "None - full price", "High (40%)", 1, "#4A7AA0" },
        { "Loyal Customers", "Bi-weekly", "Standard tier", "Selective 5%", "Medium (25%)", 2, "#7BA8B8" },
        { "Potential Loyalists", "Weekly nurture", "Eligibility offer", "Welcome 10%", "Medium (15%)", 3, "#8FA87E" },
        { "Recent Customers", "Weekly onboarding", "Eligibility offer", "First-buy 10%", "Low (10%)", 4, "#D4A762" },
        { "At Risk", "Bi-weekly re-engage", "Re-engagement", "Win-back 15%", "Low (7%)", 5, "#A05A55" },
        { "Hibernating", "Quarterly", "None", "Win-back 20%", "Minimal (3%)", 6, "#A5A29A" }
    }
)
```

After load: Sort by Column: Segment → SortOrder. Relationship: dim_Customer[Segment] → dim_Segment[Segment] (Many:1, single-direction).

**Note (D074):** `dim_Segment` is a static DAX DATATABLE (no Power Query) that merges the former `dim_SegmentOrder` (sort order + color) and `dim_SegmentActions` (CRM attributes: email cadence, loyalty tier, discount approach, budget allocation) into one 7-column dimension, per the D060 single-direction refactor. `SortOrder` is hidden; `Segment` is the displayed key, sorted by `SortOrder`.

**Note:** the recommended-action column is not held here – it lives on `dim_Customer` (SQL: `recommended_action AS action`), the customer-grain dimension. No duplication.

### dim_KPI_Selector – Enter Data

5 rows, 1 column (`KPI Name`): Total Revenue, Total Customers, Avg Order Value, Avg Recency, Revenue at Risk. **Disconnected** – no relationship to any table.

### Reactivation Rate – What-If Parameter

Modeling → New Parameter → Name: Reactivation Rate, Min: 0, Max: 50, Increment: 5, Default: 10.

---

## Relationships

The authoritative relationship list is the **Active relationships (5)** table in the Data Model section above (post-D060: 5 active, all M:1 single-direction, 0 bidirectional). It is not duplicated here, to avoid drift.

**Disconnected / standalone:** `dim_KPI_Selector` is a disconnected slicer (no relationship).

### Fact-to-fact joins: explicitly NOT used (F008, v7)

After F008 (commit `40f57f3`), the auto-detected inactive relationship `v_items_for_bi[Order ID] → sales_curated[Order ID]` was removed. The model now has **zero inactive relationships**. The deliberate design choice – consistent with Kimball star-schema discipline and the dual-grain D026 architecture – is that fact tables never join directly to other fact tables. Instead:

- **Cross-fact filter propagation** flows through shared dimensions (`dim_Customer`, `dim_Product`, `dim_Date`)
- **Order-grain ↔ line-grain reconciliation** is done via measure math, not a relationship. The `[Grain Reconciliation]` measure computes `[Total Revenue] − [Line Revenue]` and is invariant at zero. If it ever drifts from zero, the dimension-mediated join has broken – that's the signal, not a relationship line in the model
- **USERELATIONSHIP**: no DAX expression in the model uses `USERELATIONSHIP()` to activate a fact-to-fact join. The removed `Order ID` relationship had zero callers, confirming the inactive-and-unused pattern that BPA flags

**BPA delta:** "Inactive relationships that are never activated" rule 1 → 0 violations.

---

## Total: 47 measures – 46 across 6 display folders + 1 What-If parameter measure (`Reactivation Rate Value`). The `RFM Score Selector` field parameter is a table, not a measure. No orphans, no redundant calculations.

---

## Field Parameter: RFM Score Selector (Page 2)

**Created via:** Modeling → New parameter → Fields

**Fields included (in order):**
- `dim_Customer[R Score]`
- `dim_Customer[F Score]`
- `dim_Customer[M Score]`

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
