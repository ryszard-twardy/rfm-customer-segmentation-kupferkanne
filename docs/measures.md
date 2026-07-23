# DAX Measures Reference
## Kupferkanne – 109 DAX Measures (108 in 6 Display Folders + 1 What-If Parameter Measure)
### Author: Ryszard Twardy

> Source of truth for all DAX measures. Every table and column name verified against BigQuery SQL scripts (03_rfm_pipeline, 05_analytics_marts). **Since the dual-grain design (2026-05-07)**, Power BI imports `sales_curated` (order-grain fact table from script 03_rfm_pipeline) as the primary fact source. `dim_Customer` (the BI-facing customer dimension) carries the customer-grain analytics after the single-direction refactor. Model-wide hygiene policies on FormatString, SummarizeBy, Hidden, and Relationships are documented in the **Model Hygiene** section below.

---

## Data Model: Table → SQL Source Mapping

| Power BI Table | BigQuery Object | Granularity | Key Columns |
|---|---|---|---|
| **sales_curated** | `sales_curated` (TABLE) | **1 row per order (~169K)** | Order ID, Customer ID, Order Date, Order Value, Order Cost, Order Profit, Order Margin %, Dominant Category, Dominant Brand |
| **v_items_for_bi** | `v_items_for_bi` (VIEW) | **1 row per order line (~275K)** | Order ID, Product ID, Customer ID, Order Date, Quantity, Line Net Amount, Line Profit, Line Margin % |
| dim_Customer | `v_dim_customers_for_bi` (VIEW) | 1 row per customer | Customer ID, Full Name, Email, Country, Segment, Recency Days, Order Count, Total Spend, R Score, F Score, M Score, Health Score, Action |
| dim_Product | `v_dim_products_std` (VIEW) | 1 row per product | Product ID, Product Name, Brand, Margin % |
| dim_Date | Power Query (M) calendar | 1 row per day | Date, Year, Month, Year-Month, Start of Week/Month/Quarter/Year |
| dim_Segment | DAX DATATABLE | 6 rows | Segment, Email Cadence, Loyalty Tier, Discount Approach, Budget Allocation, SortOrder, SegmentColor |
| dim_KPI_Selector | DAX DATATABLE | 5 rows | KPI (disconnected) |
| Reactivation Rate | What-If Parameter | auto-generated | Reactivation Rate Value (0–50, step 5) |
| v_cohort_retention | `v_cohort_retention` (VIEW) | 1 row per cohort month × months-since-acquisition | Cohort Month, Months Since Acquisition, Active Customers, Cohort Customers, Retention Rate |
| v_revenue_new_returning | `v_revenue_new_returning` (VIEW) | 1 row per month per customer type (~77: 39 New + 38 Returning) | Revenue Month, Customer Type, Revenue, Active Customers |
*Model also contains `_Measures` (measure container) and `RFM Score Selector` (Field Parameter) - neither has a SQL source. Total model tables: 12.*

**Architecture rule:** `[Total Revenue]` and `[Total Profit]` measures pull from fact-grain `sales_curated` ONLY. Dimensional views serve as drill-down axes/legends only – pre-aggregated views break filter context across products/brands/categories.

**Active relationships (7) - verified against `relationships.tmdl`, after the single-direction refactor:**
- sales_curated[Customer ID] → dim_Customer[Customer ID] | M:1 | Single
- sales_curated[Order Date] → dim_Date[Date] | M:1 | Single
- v_items_for_bi[Customer ID] → dim_Customer[Customer ID] | M:1 | Single
- v_items_for_bi[Product ID] → dim_Product[Product ID] | M:1 | Single
- v_items_for_bi[Order Date] → dim_Date[Date] | M:1 | Single - **date-slicing for the line-grain measures**
- dim_Customer[Segment] → dim_Segment[Segment] | M:1 | Single - **re-pointed onto the merged dim_Segment**
- v_revenue_new_returning[Revenue Month] → dim_Date[Date] | M:1 | Single - **monthly date-slicing for the New vs Returning area chart**

**Retiring `v_rfm_for_bi`:** dropped the table and its 3 relationships – `[Customer ID] ↔ dim_Customer` (a former bidirectional join, since superseded), `[Last Order Date] → dim_Date`, and `[Segment] → dim_SegmentOrder`. Segment filter propagation is preserved single-direction via `dim_Customer[Segment] → dim_Segment[Segment]`. Bidirectional count: 2 → **1**.

**Merging the segment dimensions:** `dim_SegmentOrder` + `dim_SegmentActions` merged into a single `dim_Segment` (DAX DATATABLE), and the segment relationship re-pointed onto `dim_Segment[Segment]`. The 1:1 bidirectional was dropped. Bidirectional count: 1 → **0** (end state).

---

## Model Hygiene

The conventions below are model-wide metadata policies. They change no measure expressions and no display-folder structure. Every measure and column in this document conforms to them.

### Format String Standards

Per BPA rule **"Provide format string for measures"**, every numeric measure carries an explicit `FormatString`. Conventions:

| Semantic | FormatString | Example measures |
|---|---|---|
| Currency (EUR) | `"€"#,##0.00;-"€"#,##0.00` | `[Total Revenue]`, `[Avg Order Value]`, `[ARPU by Country]` |
| Currency (compact display) | inherited Currency + visual-level "Display units = Millions" | `[Total Revenue]`, `[Total Profit]` on KPI cards |
| Percentage | `0.00%` | `[Profit Margin %]`, `[Revenue % of Total]`, `[Country Revenue Share]` |
| Count (integer) | `#,##0` | `[Total Customers]`, `[Total Orders]`, `[Distinct Orders]` |
| Decimal (small score) | `0.00` | `[Avg R Score]`, `[Avg F Score]`, `[Avg M Score]` |
| Date | `dd-mmm-yyyy` | calc-table date columns |
| Text | *(none – no FormatString applied)* | `[Health Indicator]`, `[Subtitle Page N]`, `[Top Brand Name]` |

**Coverage:** 55 of 109 measures carry an explicit `FormatString`. The 54 without: 53 intentional text measures + `[Dynamic KPI Selector]` (format inherited at evaluation via `SWITCH`). Three special-case formats preserved:
- `[Avg Health Score]` → `0.0 "/ 15"` (score-out-of-15 semantic)
- `[Reactivation Rate Value]` → `0` (integer percentage points, not a ratio)
- `[Dynamic KPI Selector]` → format inherited via `SWITCH` from the selected measure

**Batch script:** `tools/format_string_batch.csx` (`dryRun=true` default, explicit manual-override helper, BPA pre-flight via `INFO.VIEW.MEASURES()` introspection). Reference implementation for future TE2 pattern-matching batches. The BPA "Provide format string for measures" rule currently reports 54 flags, all intentional – see the coverage note above.

**BPA accepted exception – percentage decimals.** The BPA rule "Format string for percentages should show one decimal" flags every percentage measure. The house standard for precision-sensitive percentages (margins, rates) is `0.00%` (2dp), where the second decimal carries real information; this is a deliberate convention, not a defect, accepted as a standing exception (mirrors the accepted `Is Closed Month` exception). Affected 2dp measures (the 11 precision-sensitive percentage measures use `0.00%`): `Segment % of Total`, `Revenue % of Total`, `Country Revenue Share`, `Profit Margin %`, `Avg Brand Margin %`, `Line Margin %`, `Margin Baseline`, `% Revenue at Risk`, `Cumulative Revenue %`, `Pareto Threshold 80%`, `Profit Margin PY`. The 1dp (`0.0%`) exceptions are three year-over-year measures – `Revenue YoY %`, `Profit YoY %`, and `Profit Margin YoY (pp)` – where a single decimal is sufficient for a year-over-year delta.

### Column Behavior: SummarizeBy = None

Per BPA rule **"Do not summarize numeric columns"** and the force-explicit-measure pattern, every non-additive numeric column on the fact and dimension tables has `SummarizeBy = None`. Users cannot drag a column onto a visual and get an implicit `SUM`, `COUNT`, or `AVERAGE` – they must select a named measure.

**Why:** implicit aggregations have no `FormatString`, no documentation, no name. They drift silently as schemas evolve. Forcing explicit measures keeps the semantic layer honest and visible in the Fields pane.

**Scope – 38 columns (applied via `tools/format_summarize_by_batch.csx`):**

| Table | Cols | Columns |
|---|---|---|
| `dim_Customer` | 11 | Recency Days, Order Count, Total Spend, Total Profit, Margin %, Total Units, Avg Products per Order, R Score, F Score, M Score, Health Score |
| `dim_Date` | 6 | Year, Month, Week of Year, Day, Day Number, Year-Month-Number |
| `dim_Segment` | 1 | SortOrder |
| `sales_curated` | 9 | Order Discount %, Basket Item Count, Order Value, Order Cost, Order Profit, Order Margin %, Total Units, Distinct Products, Source Month |
| `v_items_for_bi` | 4 | Quantity, Line Net Amount, Line Profit, Line Margin % |
| `dim_KPI_Selector` | 1 | SortOrder |
| `v_cohort_retention` | 4 | Months Since Acquisition, Active Customers, Cohort Customers, Retention Rate |
| `v_revenue_new_returning` | 2 | Revenue, Active Customers |

**Batch script:** `tools/format_summarize_by_batch.csx` (explicit `(table, column)` targets list – no pattern matching, per audit precision). Uses `KeyValuePair<string,string>` for TE2 Roslyn pre-C# 7.0 compatibility. BPA delta: 28 → 0 violations.

`SummarizeBy = None` and `isHidden` are independent properties – a column can be `SummarizeBy = None` and still visible (`dim_Date[Year]`), or both `SummarizeBy = None` and hidden (`dim_Customer[Order Count]`).

### Foreign Key & Surrogate Key Visibility

Per BPA rule **"Hide foreign keys"** and Kimball / SQLBI defensive star-schema UX (Russo + Ferrari, *Definitive Guide to DAX*; Kimball, *Data Warehouse Toolkit*), keys that exist only to wire relationships are hidden; keys that double as user-facing attributes stay visible on their dimension.

**Why (three rationales):**
1. **Remove plumbing from the Fields pane** – `Customer ID` and `Product ID` are surrogate keys users never filter on directly (they filter by `Full Name`, `Country`, `Brand`, `Product Category`). Both are hidden on every table that carries them, fact and dimension alike. Keys that are themselves attributes – `Order Date` → `dim_Date[Date]`, `Segment` → `dim_Segment[Segment]` – stay visible so users can use them.
2. **Enforce correct filter propagation** – in a single-direction star, filters flow from dimensions to facts. Dragging an FK from a fact creates a one-table-only filter context. Hiding the fact-side FK forces use of the dimension column, so a `dim_Customer` filter propagates to both `sales_curated` and `v_items_for_bi`.
3. **Block implicit COUNT measures** – FK columns are Int/Text/DateTime. Hiding them pairs with the `SummarizeBy = None` policy and the force-explicit-measure pattern to fully block implicit aggregations.

**Hidden – relationship & degenerate keys (retopologised in the single-direction refactor):**

| Table | Hidden key column(s) | Class |
|---|---|---|
| `dim_Customer` | `Customer ID` | PK / target of two fact FKs |
| `dim_Product` | `Product ID` | PK / target of `v_items_for_bi` FK |
| `sales_curated` | `Customer ID`, `Order Date` | FK → `dim_Customer`, `dim_Date` |
| `sales_curated` | `Order ID` | degenerate dimension (no relationship) |
| `v_items_for_bi` | `Customer ID`, `Product ID`, `Order Date` | FK → `dim_Customer`, `dim_Product`, `dim_Date` |
| `v_items_for_bi` | `Order ID` | degenerate dimension (inactive relationship removed) |

Visible keys: `dim_Date[Date]` and `dim_Segment[Segment]` – user-facing attributes, not pure plumbing.

**RFM analytic payload on `dim_Customer`:** the single-direction refactor folded the former `v_rfm_for_bi` satellite into `dim_Customer`. Its scoring columns – `M Score`, `Health Score`, `Order Count` – are hidden and surfaced through measures (`[Avg R Score]`, `[Avg Health Score]`, …) and referenced by name in the Page-2 Field Parameter (field parameters resolve source columns regardless of visibility); `R Score` and `F Score` are now visible (draggable score axes for the Page 5 RFM heatmap). Before the merge these stayed visible under the earlier dual-grain satellite exception; after the merge that exception no longer applies. Descriptive attributes (`Full Name`, `Country`, `Last Order Date`, `RFM Cell`, `Action`) remain visible, as do `Recency Days` and the monetary analytics `Total Spend` and `Total Profit`. `Total Spend` is intentionally visible (paired with `Total Profit`, #18) despite the BPA "Hide fact table columns" rule; the flag is accepted, not actioned.

**What does NOT change after hiding the keys:**
- Relationships remain functional – the engine resolves keys even when hidden
- Existing measures unaffected – explicit DAX references columns regardless of `isHidden`
- Storage / query performance unchanged – `isHidden` is UI-only

### Hidden Fact Columns

Four fact-source value columns are hidden so users reach them only through the canonical measures:
- `sales_curated[Order Value]`, `[Order Profit]`
- `v_items_for_bi[Line Net Amount]`, `[Line Profit]`

These remain accessible via `[Total Revenue]`, `[Total Profit]`, `[Line Revenue]`, `[Line Profit]`, which reference the columns explicitly in DAX.

**Total hidden: 21 columns model-wide** – 18 deliberately managed (9 relationship/degenerate keys, 4 fact-source value columns, 3 RFM payload columns on `dim_Customer`, 1 sort helper (`dim_Segment[SortOrder]`), 1 closed-month flag (`dim_Date[Is Closed Month]`)), plus 3 Power BI auto-generated system columns (the `_Measures` container column and the two `RFM Score Selector` field-parameter columns).

---

## Folder: 01 – Core KPIs

| Measure | Formula | Format | Pages |
|---|---|---|---|
| Total Revenue | `SUM(sales_curated[Order Value])` | € Currency (€ DE), 2dp, display Millions | 1, 2, 3, 5, 6, 7 |
| Total Customers | `CALCULATE(DISTINCTCOUNT(dim_Customer[Customer ID]), NOT ISBLANK(dim_Customer[Order Count]))` | # 0dp | 1, 2, 4, 5, 6 |
| Customers at Risk | `CALCULATE(DISTINCTCOUNT(dim_Customer[Customer ID]), dim_Customer[Segment] IN {"At Risk", "Hibernating"}, NOT ISBLANK(dim_Customer[Order Count]))` | # 0dp | 4 |
| Total Orders | `SUM(dim_Customer[Order Count])` | # 0dp | 7 |
| Avg Order Value | `DIVIDE([Total Revenue], [Total Orders], 0)` | € Currency, 2dp | 7 |
| Avg Customer LTV | `DIVIDE([Total Revenue], [Total Customers], 0)` | € Currency, 0dp | – |
| Avg Recency Days | `AVERAGE(dim_Customer[Recency Days])` | Custom `#,##0 "days"` | 1, 2 |
| Median Recency Days | `MEDIAN(dim_Customer[Recency Days])` | Custom `#,##0 "days"` | 4 |
| Avg Frequency | `AVERAGE(dim_Customer[Order Count])` | Dec 1dp | 2 |
| Avg Monetary | `AVERAGE(dim_Customer[Total Spend])` | € Currency, 2dp | 2 |
| Median Total Spend | `MEDIAN(dim_Customer[Total Spend])` | € Currency, 2dp | 4 |
| Distinct Orders | `DISTINCTCOUNT(sales_curated[Order ID])` | # 0dp | 4 |
| Total Profit | `SUM(sales_curated[Order Profit])` | € Currency (€ DE), 2dp, display Millions | 1 |
| Profit Margin % | `DIVIDE([Total Profit], [Total Revenue], 0)` | % 2dp | 1, 3 |
| Line Revenue | `SUM(v_items_for_bi[Line Net Amount])` | € Currency, 2dp | – |
| Line Profit | `SUM(v_items_for_bi[Line Profit])` | € Currency, 2dp | – |
| Line Margin % | `DIVIDE([Line Profit], [Line Revenue], 0)` | % 2dp | – |
| Line Quantity | `SUM(v_items_for_bi[Quantity])` | # 0dp | 3 |
| Grain Reconciliation | `[Total Revenue] - [Line Revenue]` | € Currency, 2dp | – |
| Total Products | `DISTINCTCOUNT(dim_Product[Product ID])` | # 0dp | 3 |
| Total Brands | `DISTINCTCOUNT(dim_Product[Brand])` | # 0dp | 3 |
| Top Brand Revenue | `MAXX(VALUES(dim_Product[Brand]), [Line Revenue])` | € Currency, display Millions | 3 |
| Top Brand Name | VAR pattern – see formula block below | Text | 3 |
| Avg Brand Margin % | `AVERAGEX(VALUES(dim_Product[Brand]), [Line Margin %])` | % 2dp | – |
| Margin Baseline | `CALCULATE([Line Margin %], REMOVEFILTERS(dim_Product[Brand]))` | % 2dp | 3 |
| Top Category Revenue | `MAXX(VALUES(dim_Product[Product Category]), [Line Revenue])` | € Currency, display Millions | 3 |
| Top Category Name | VAR pattern – see formula block below | Text | 3 |
| Lifecycle Revenue | `SUM(v_revenue_new_returning[Revenue])` | € Currency, 2dp | 5 |

**Dependency / diagnostic measures (Pages = –):** `Line Revenue`, `Line Profit`, `Line Margin %` are line-grain building blocks consumed by the brand/category measures (`[Top Brand Revenue]`, `[Avg Brand Margin %]`, …); `Grain Reconciliation` (`[Total Revenue] - [Line Revenue]`) is a QA invariant (expected 0). None are bound to a visual directly.

**`[Distinct Orders]` (Pages = 4):** order-grain distinct order count from `sales_curated[Order ID]`. Not slice-able by `dim_Product` – `sales_curated` has no relationship path to `dim_Product` in the single-direction star, so a product slice returns the unfiltered grand total. Bound on the Page 4 scatter; do not place on a product axis.

**Weighted margin principle:** `Profit Margin %` uses `SUM(profit) / SUM(revenue)`, never `AVERAGE(margin_pct)`. Arithmetic mean of percentages misrepresents aggregate when orders have different sizes.

**Equal-weight benchmark:** `Avg Brand Margin %` uses `AVERAGEX` over brands – equal-weight semantic for benchmarking, NOT P&L. Returns 59.94% vs `Profit Margin %` 59.78% (revenue-weighted) – the two now sit close but remain distinct semantics. Both legitimate, qualifying labels mandatory in UI ("Average Brand Margin", never "Margin").

**Margin Baseline:** `Margin Baseline` = `CALCULATE([Line Margin %], REMOVEFILTERS(dim_Product[Brand]))` – the revenue-weighted overall line margin, flat across the Brand axis (59.78%). Drives the Page 3 brand combo reference line, replacing the prior built-in equal-weight Average line (which violated the weighted-margin principle). Rendered as a hidden secondary-axis series anchoring an Average analytics line (Average of a flat series returns the flat value), giving an edge-to-edge labelled reference with full DAX control.

**Fact-grain principle (dual-grain naming):** measures `[Total Revenue]` and `[Total Profit]` refactored to source from `sales_curated` (order-grain fact table). Dimensional views serve as drill-down axes/legends only.

### Customers at Risk – full formula

```dax
Customers at Risk =
CALCULATE (
    DISTINCTCOUNT ( dim_Customer[Customer ID] ),
    dim_Customer[Segment] IN { "At Risk", "Hibernating" },
    NOT ISBLANK ( dim_Customer[Order Count] )
)
```

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

### Lifecycle Revenue – full formula

```dax
Lifecycle Revenue =
SUM ( v_revenue_new_returning[Revenue] )
```

---

## Folder: 02 – RFM Scores

| Measure | Formula | Format | Pages |
|---|---|---|---|
| Avg R Score | `AVERAGE(dim_Customer[R Score])` | Dec 1dp | 2 |
| Avg F Score | `AVERAGE(dim_Customer[F Score])` | Dec 1dp | 2 |
| Avg M Score | `AVERAGE(dim_Customer[M Score])` | Dec 1dp | 2 |
| Avg Health Score | `AVERAGE(dim_Customer[Health Score])` | Dec 1dp | 2 |
| Customer Recency Days | `SELECTEDVALUE(dim_Customer[Recency Days])` | `#,##0 "days"` | 7 |
| Customer Health Score | `SELECTEDVALUE(dim_Customer[Health Score])` | `0 "/ 15"` | 7 |
| Customer RFM Label | VAR pattern – see formula block below | Text | 7 |

The `Customer *` measures are single-customer drillthrough readouts for Page 7 (Customer Drillthrough) – a page hidden by design, reached from any customer context rather than shown as its own tab; each is `BLANK` unless exactly one `dim_Customer` row is in context.

```dax
Customer RFM Label =
VAR RScore =
    SELECTEDVALUE ( dim_Customer[R Score] )
VAR FScore =
    SELECTEDVALUE ( dim_Customer[F Score] )
VAR MScore =
    SELECTEDVALUE ( dim_Customer[M Score] )
RETURN
    IF (
        NOT ISBLANK ( RScore ),
        "R" & RScore
            & " · F" & FScore
            & " · M" & MScore
    )
```

---

## Folder: 03 – Segment Analysis

| Measure | Format | Pages |
|---|---|---|
| Segment % of Total | % 2dp | 1, 2 |
| Revenue % of Total | % 2dp | 2 |
| Revenue at Risk | € 0dp | 1, 4 |
| % Revenue at Risk | % 2dp | 4 |
| Cumulative Revenue % | % 2dp | 5 |
| Pareto Threshold 80% | % 2dp | 5 |

```dax
Segment % of Total =
VAR SegmentCount =
    CALCULATE (
        COUNTROWS ( dim_Customer ),
        NOT ISBLANK ( dim_Customer[Order Count] )
    )
VAR TotalCount =
    CALCULATE (
        COUNTROWS ( dim_Customer ),
        ALL ( dim_Customer ),
        NOT ISBLANK ( dim_Customer[Order Count] )
    )
RETURN
    DIVIDE (
        SegmentCount,
        TotalCount,
        0
    )
```

```dax
Revenue % of Total =
VAR SegmentRevenue =
    SUM ( dim_Customer[Total Spend] )
VAR TotalRevenue =
    CALCULATE (
        SUM ( dim_Customer[Total Spend] ),
        ALL ( dim_Customer )
    )
RETURN
    DIVIDE (
        SegmentRevenue,
        TotalRevenue,
        0
    )
```

```dax
Revenue at Risk =
CALCULATE (
    SUM ( dim_Customer[Total Spend] ),
    dim_Customer[Segment]
        IN {
            "At Risk",
            "Hibernating"
        }
)
```

```dax
% Revenue at Risk =
VAR RiskRevenue = [Revenue at Risk]
VAR TotalRevenue =
    CALCULATE (
        SUM ( dim_Customer[Total Spend] ),
        ALL ( dim_Customer )
    )
RETURN
    DIVIDE ( RiskRevenue, TotalRevenue, 0 )
```

```dax
Cumulative Revenue % =
VAR CurrentDecile = SELECTEDVALUE ( dim_Customer[Customer Decile] )
VAR TotalSpend =
    CALCULATE (
        SUM ( dim_Customer[Total Spend] ),
        ALL ( dim_Customer )
    )
VAR CumSpend =
    CALCULATE (
        SUM ( dim_Customer[Total Spend] ),
        FILTER ( ALL ( dim_Customer ), dim_Customer[Customer Decile] <= CurrentDecile )
    )
RETURN
    DIVIDE ( CumSpend, TotalSpend )
```

```dax
Pareto Threshold 80% =
0.8
```

**Calculated column `dim_Customer[Customer Decile]`:** visible, SummarizeBy=None, FormatString `0`, with a `///` description. Buckets customers into 10 equal bands by `Total Spend` (1 = top 10%) – the Pareto X-axis consumed by `[Cumulative Revenue %]`. Uses `RANKX` over `dim_Customer[Total Spend]` with `DESC, Skip` (Skip, not Dense, so each customer gets a distinct rank and the 10-band `INT` bucketing stays even). A **calculated column**, not a measure – excluded from the measure total; like `dim_Date[Is Closed Month]` it is tracked here and sits outside the 32-column SummarizeBy=None batch scope.

```dax
Customer Decile =
VAR N = COUNTROWS ( ALL ( dim_Customer ) )
VAR Rnk =
    RANKX (
        ALL ( dim_Customer ),
        dim_Customer[Total Spend],
        ,
        DESC,
        Skip
    )
RETURN
    INT ( DIVIDE ( ( Rnk - 1 ) * 10, N ) ) + 1
```

---

## Folder: 04 – Time Intelligence

| Measure | Format | Pages |
|---|---|---|
| Revenue Active (0–90d) | € 0dp | 4 |
| Revenue Cooling (91–180d) | € 0dp | 4 |
| Revenue Dormant (180d+) | € 0dp | 4 |
| Revenue Rolling 12M | € 0dp | 1 |
| Revenue YoY % | % 1dp | – |
| Profit YoY % | % 1dp | – |
| Profit Margin YoY (pp) | % 1dp | – |
| Revenue PY | € 2dp | – |
| Profit PY | € 2dp | – |
| Profit Margin PY | % 2dp | – |

```dax
Revenue Active =
CALCULATE (
    SUM ( dim_Customer[Total Spend] ),
    dim_Customer[Recency Days] <= 90
)

Revenue Cooling =
CALCULATE (
    SUM ( dim_Customer[Total Spend] ),
    dim_Customer[Recency Days] > 90
        && dim_Customer[Recency Days] <= 180
)

Revenue Dormant =
CALCULATE (
    SUM ( dim_Customer[Total Spend] ),
    dim_Customer[Recency Days] > 180
)
```

`[Revenue Rolling 12M]` – Total Revenue over the trailing 12 months ending at the date context (EUR); blank past the last sales date and before the first full 12-month trailing window. The dual guard (`FirstSalesDate` / `LastSalesDate` / `PointDate` / `WindowStart`) stops the rolling series from decaying past real data and from ramping through a partial first window. Rendered on the Page 1 trend secondary axis (dashed, subordinate).

```dax
Revenue Rolling 12M =
VAR FirstSalesDate =
    CALCULATE ( MIN ( sales_curated[Order Date] ), REMOVEFILTERS () )
VAR LastSalesDate =
    CALCULATE ( MAX ( sales_curated[Order Date] ), REMOVEFILTERS () )
VAR PointDate =
    MAX ( dim_Date[Date] )
VAR WindowStart =
    EDATE ( PointDate, -12 ) + 1
VAR Result =
    CALCULATE (
        [Total Revenue],
        DATESINPERIOD ( dim_Date[Date], PointDate, -12, MONTH )
    )
RETURN
    IF (
        MIN ( dim_Date[Date] ) <= LastSalesDate
            && WindowStart >= FirstSalesDate,
        Result
    )
```

`[Revenue YoY %]` – year-over-year change of Total Revenue vs the same period last year (the current open month reads low against a full prior-year month).

```dax
Revenue YoY % =
VAR CurrentRevenue = [Total Revenue]
VAR PriorRevenue =
    CALCULATE (
        [Total Revenue],
        SAMEPERIODLASTYEAR ( dim_Date[Date] )
    )
RETURN
    DIVIDE ( CurrentRevenue - PriorRevenue, PriorRevenue )
```

`[Profit YoY %]` – year-over-year change of Total Profit vs the same period last year (the current open month reads low against a full prior-year month).

```dax
Profit YoY % =
VAR CurrentProfit = [Total Profit]
VAR PriorProfit =
    CALCULATE (
        [Total Profit],
        SAMEPERIODLASTYEAR ( dim_Date[Date] )
    )
RETURN
    DIVIDE ( CurrentProfit - PriorProfit, PriorProfit )
```

`[Profit Margin YoY (pp)]` – year-over-year change in the revenue-weighted profit margin vs the same period last year, as a percentage-point delta (stored as a ratio, so 0.02 renders 2.0%).

```dax
Profit Margin YoY (pp) =
VAR CurrentMargin = [Profit Margin %]
VAR PriorMargin =
    CALCULATE (
        [Profit Margin %],
        SAMEPERIODLASTYEAR ( dim_Date[Date] )
    )
RETURN
    IF ( NOT ISBLANK ( PriorMargin ), CurrentMargin - PriorMargin )
```

`[Revenue PY]`, `[Profit PY]`, `[Profit Margin PY]` – prior-year values of Total Revenue, Total Profit, and the revenue-weighted profit margin for the same period. All the time-intelligence measures above blank naturally in the first sales year, where there is no prior period, matching `[Revenue YoY %]`.

```dax
Revenue PY =
CALCULATE (
    [Total Revenue],
    SAMEPERIODLASTYEAR ( dim_Date[Date] )
)

Profit PY =
CALCULATE (
    [Total Profit],
    SAMEPERIODLASTYEAR ( dim_Date[Date] )
)

Profit Margin PY =
CALCULATE (
    [Profit Margin %],
    SAMEPERIODLASTYEAR ( dim_Date[Date] )
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
    CALCULATE (
        SUM ( dim_Customer[Total Spend] ),
        dim_Customer[Segment]
            IN {
                "At Risk",
                "Hibernating"
            }
    )
VAR Rate =
    SELECTEDVALUE (
        'Reactivation Rate'[Reactivation Rate],
        10
    ) / 100
RETURN
    AtRiskRev * Rate
```

```dax
Dynamic KPI Selector =
VAR Selected =
    SELECTEDVALUE (
        dim_KPI_Selector[KPI],
        "Total Revenue"
    )
RETURN
    SWITCH (
        Selected,
        "Total Revenue", [Total Revenue],
        "Total Customers", [Total Customers],
        "Average Order Value", [Avg Order Value],
        "Average Recency Days", [Avg Recency Days],
        "Revenue at Risk", [Revenue at Risk],
        [Total Revenue]
    )
```

**What-If parameter measure (no display folder):** `Reactivation Rate Value` = `SELECTEDVALUE('Reactivation Rate'[Reactivation Rate], 10)` (format `0`) lives on the `Reactivation Rate` what-if parameter table, not in a display folder. It is the auto-generated parameter value; `[What-If Revenue Impact]` consumes the parameter. Not bound to any visual.

---

## Folder: 06 – Formatting & Regional

| Measure | Purpose | Format | Pages |
|---|---|---|---|
| Health Indicator | Status text from health_score | Text | – |
| ARPU by Country | Revenue per customer (context-aware) | € 2dp | 6 |
| Country Revenue Share | Country share of total revenue | % 2dp | 6 |
| Segment Color | Hex color per segment (SWITCH) – USE ONLY IF dim_Segment[SegmentColor] column is not used for conditional formatting | Hex text | – |
| Revenue Trend Chart Title | Dynamic line chart title with live month count | Text | 1 |
| Subtitle Page 1 | Dynamic Page 1 subtitle with live market + month counts | Text | 1 |
| Subtitle Page 2 | Dynamic Page 2 subtitle with live segment count | Text | 2 |
| Subtitle Page 3 | Dynamic Page 3 subtitle with product + brand counts | Text | 3 |
| Subtitle Page 4 | Dynamic Page 4 subtitle with live at-risk customer count | Text | 4 |
| Subtitle Page 5 | Static Page 5 subtitle literal (RFM distribution, revenue concentration, cohort retention, segment migration) | Text | 5 |
| Subtitle Page 6 | Dynamic Page 6 subtitle with live market and city counts, singular/plural-aware | Text | 6 |
| Subtitle Page 7 | Dynamic Page 7 drillthrough header (customer ID · segment · city, country); prompts the drill-through gesture when no single customer is in context | Text | 7 |
| R Label | Static axis caption for the RFM Field Parameter | Text | 2 |
| M Label | Static axis caption for the RFM Field Parameter | Text | 2 |
| F Label | Static axis caption for the RFM Field Parameter | Text | 2 |
| Combo Chart Title | Dynamic Page 3 combo chart title with top brand name + revenue | Text | 3 |
| Subtitle Cohort Retention | Dynamic Page 5 cohort-matrix subtitle: cohort count, span, tenure window | Text | 5 |
| Retention Font Color | Per-cell font contrast for the diverging cohort heatmap | Hex text | 5 |
| Lifecycle Headline | Dynamic Page 5 headline: repeat-customer share of revenue | Text | 5 |
| Map Title | Dynamic Page 6 map title, three-state: region drill, country selection, default DACH headline | Text | 6 |
| Map Subtitle | Dynamic Page 6 map subtitle: grain word plus EUR total, selection-aware | Text | 6 |
| Market Ranking Title | Page 6 combo title: reach-not-basket claim by default, neutral under filters | Text | 6 |
| Market Ranking Subtitle | Dynamic Page 6 combo subtitle: clustering claim gated on 2+ visible markets | Text | 6 |
| Region Filter Active | Drill signal (ALLSELECTED-guarded): 1 only when a direct State/Region filter is active | Whole # | 6 |
| Country Filter Active | Country selection signal (subset-aware, ALLSELECTED-guarded): 1 only on a proper-subset Country selection | Whole # | 6 |
| Country Total Revenue | Country-grain revenue immune to the Region slicer (choropleth fill driver) | € 2dp | 6 |
| Subtitle Segment Strategy | Static subtitle for the Recommended Strategy by Segment table | Text | 2 |
| Subtitle Segment Scatter | Static subtitle for the Frequency x Monetary by Segment scatter chart | Text | 2 |
| Subtitle Brand Margin | Static data-claim subtitle for the Page 3 brand combo chart - revalidate if margin ranking changes | Text | 3 |
| Subtitle Recency Stages | Static subtitle for the Revenue by recency stage chart (90/180-day cooling curve) | Text | 4 |
| Subtitle Risk Concentration | Static subtitle for the Where the risk concentrates table | Text | 4 |
| Subtitle Winback Scatter | Static subtitle for the Who to win back scatter chart | Text | 4 |
| Subtitle Pareto | Static subtitle for the Revenue Concentration (Pareto) chart | Text | 5 |
| Subtitle New Returning | Static subtitle for the New vs Returning revenue chart | Text | 5 |
| Subtitle RFM Heatmap | Static subtitle for the RFM Distribution Map | Text | 5 |
| Subtitle Revenue Trend | Dynamic Page 1 subtitle with subset-aware segment and market counts | Text | 1 |
| Subtitle Whatif Upside | Dynamic Page 4 subtitle injecting the live What-If reactivation rate | Text | 4 |
| Title Recency Stages | Static Page 4 title for the Revenue by recency stage chart | Text | 4 |
| Title Risk Concentration | Static Page 4 title for the Where the risk concentrates table | Text | 4 |
| Title Winback Scatter | Static Page 4 title for the Who to win back scatter chart | Text | 4 |
| Title Whatif Upside | Static Page 4 title for the Upside of acting chart | Text | 4 |
| Title Pareto | Static Page 5 title for the Revenue Concentration (Pareto) chart | Text | 5 |
| Title RFM Heatmap | Static Page 5 title for the RFM Distribution Map | Text | 5 |
| Title Segment Strategy | Static Page 2 title for the Recommended Strategy by Segment table | Text | 2 |
| Title Segment Scatter | Static Page 2 title for the Frequency x Monetary by Segment scatter chart | Text | 2 |
| Title Cohort Retention | Static Page 5 title for the Cohort Retention Heatmap | Text | 5 |
| Title Revenue by Segment | Static Page 1 title for the Revenue by Segment bar chart | Text | 1 |
| Title Recency Histogram | Static Page 1 title for the Customer Count by Recency histogram | Text | 1 |
| Title Segment Distribution | Static Page 1 title for the Customer Distribution by Segment donut chart | Text | 1 |
| Title Top Products | Static Page 3 title for the Top 15 Products by Revenue chart | Text | 3 |
| Title Profitability Matrix | Static Page 3 title for the Profitability by Category, Brand and Product matrix | Text | 3 |
| Title Category Trend | Static Page 3 title for the Revenue Trend by Category chart | Text | 3 |
| Title Segment Profile | Static Page 2 title for the Segment Profile Comparison table | Text | 2 |
| Title Revenue by RFM | Static Page 2 title for the Revenue by RFM Score chart | Text | 2 |

```dax
Health Indicator =
VAR Score =
    AVERAGE ( dim_Customer[Health Score] )
RETURN
    SWITCH (
        TRUE (),
        Score >= 11, "● Healthy",
        Score >= 7, "◐ Monitor",
        "○ Critical"
    )
```

```dax
ARPU by Country =
DIVIDE (
    SUM ( dim_Customer[Total Spend] ),
    CALCULATE (
        COUNTROWS ( dim_Customer ),
        NOT ISBLANK ( dim_Customer[Order Count] )
    ),
    0
)
```

```dax
Country Revenue Share =
DIVIDE (
    SUM ( dim_Customer[Total Spend] ),
    CALCULATE (
        SUM ( dim_Customer[Total Spend] ),
        ALL ( dim_Customer )
    ),
    0
)
```

```dax
Segment Color =
SWITCH (
    SELECTEDVALUE ( dim_Customer[Segment] ),
    "Champions", "#4A7AA0",
    "Loyal Customers", "#7BA8B8",
    "Potential Loyalists", "#8FA87E",
    "Recent Customers", "#D4A762",
    "At Risk", "#A05A55",
    "Hibernating", "#A5A29A",
    "#94A3B8"
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
"Kupferkanne – D2C E-commerce · "
    & DISTINCTCOUNT ( dim_Customer[Country] )
    & " European markets · Rolling "
    & DISTINCTCOUNT ( sales_curated[Source Month] )
    & " months"
```

**Design decision – Subtitle Page 1 market count:** the market count is now dynamic via `DISTINCTCOUNT ( dim_Customer[Country] )`, matching the rolling-months pattern; both counters self-correct as geography or the calendar extends (replacing the static `9 European markets` literal).

```dax
Subtitle Page 2 =
"RFM profile comparison across "
    & DISTINCTCOUNT ( dim_Segment[Segment] )
    & " segments"
```

```dax
Subtitle Page 3 = 
"Profitability across " & [Total Products] & " products and " & [Total Brands] & " brands"
```

```dax
Subtitle Page 4 =
"Revenue at risk across "
    & FORMAT ( [Customers at Risk], "#,##0" )
    & " at-risk and hibernating customers"
```

```dax
Subtitle Page 5 = "RFM space distribution, revenue concentration, cohort retention, segment migration"
```

```dax
Subtitle Page 6 =
VAR _Markets =
    DISTINCTCOUNT ( dim_Customer[Country] )
VAR _Cities =
    DISTINCTCOUNT ( dim_Customer[City] )
RETURN
    "Geographic performance across "
        & _Markets & IF ( _Markets = 1, " market", " markets" )
        & " and "
        & _Cities & IF ( _Cities = 1, " city", " cities" )
```

```dax
Subtitle Page 7 =
VAR HasCustomer =
    HASONEVALUE ( dim_Customer[Customer ID] )
RETURN
    IF (
        HasCustomer,
        SELECTEDVALUE ( dim_Customer[Customer ID] )
            & " · " & SELECTEDVALUE ( dim_Customer[Segment] )
            & " · " & SELECTEDVALUE ( dim_Customer[City] )
            & ", " & SELECTEDVALUE ( dim_Customer[Country] ),
        "Right-click a customer on any page and choose Drill through"
    )
```

**Design decision – Subtitle Page N convention:** All page subtitles follow `Subtitle Page N` naming convention for consistency across Pages 1-7. All bound via fx → Field value to subtitle text boxes.

`[Subtitle Page 3]` is **bound** – via fx → Field value on the Page 3 subtitle text box.

`[Subtitle Page 5]` is **static** – a plain literal (unlike the live, dynamic Pages 1-4 subtitles).

```dax
Combo Chart Title =
"Brand Revenue x Margin % - top brand "
    & [Top Brand Name]
    & " drives "
    & FORMAT ( [Top Brand Revenue], "€#,##0,,.0M" )
```

**Design decision – dynamic combo title:** the Page 3 brand combo chart binds its Title to `[Combo Chart Title]` via fx (Field value), following the `[Revenue Trend Chart Title]` pattern. The headline brand and its compact-formatted revenue come from `[Top Brand Name]` and `FORMAT ( [Top Brand Revenue], "€#,##0,,.0M" )`, so the title auto-updates under slicer context – no manual edits as the leader changes.

```dax
Subtitle Cohort Retention =
VAR _cohorts =
    DISTINCTCOUNT ( v_cohort_retention[Cohort Month] )
VAR _minMonth =
    FORMAT ( MIN ( v_cohort_retention[Cohort Month] ), "MMM yyyy" )
VAR _maxMonth =
    FORMAT ( MAX ( v_cohort_retention[Cohort Month] ), "MMM yyyy" )
VAR _window =
    MAX ( v_cohort_retention[Months Since Acquisition] )
RETURN
    _cohorts & " cohorts, "
        & _minMonth & " to " & _maxMonth
        & ", tenure 0 to " & _window & " months"
```

```dax
Retention Font Color =
VAR _rate =
    SUM ( v_cohort_retention[Retention Rate] )
RETURN
    SWITCH (
        TRUE (),
        _rate >= 0.70, "#FFFFFF",
        _rate <= 0.25, "#FFFFFF",
        "#3D4752"
    )
```

**Design decision – Page 5 cohort measures:** `[Subtitle Cohort Retention]` is bound via fx (Field value) to the cohort matrix subtitle, reporting the live cohort count, calendar span, and tenure window. `[Retention Font Color]` drives per-cell font color on the diverging heatmap – white at both extremes (retention >= 0.70 and <= 0.25) and dark ink (`#3D4752`) in the cream center, because a single threshold rule whitens the light center of a diverging scheme. Both reference the standalone `v_cohort_retention` import.

```dax
Lifecycle Headline =
VAR _returning =
    CALCULATE ( [Lifecycle Revenue], v_revenue_new_returning[Customer Type] = "Returning" )
VAR _share =
    DIVIDE ( _returning, [Lifecycle Revenue] )
RETURN
    "Repeat customers drive ~" & FORMAT ( MROUND ( _share * 100, 5 ), "0" ) & "% of revenue"
```

```dax
Map Title =
VAR _Markets =
    DISTINCTCOUNT ( dim_Customer[Country] )
VAR _Regions =
    DISTINCTCOUNT ( dim_Customer[State] )
VAR _GrandTotal =
    CALCULATE ( [Total Revenue], REMOVEFILTERS ( dim_Customer ) )
VAR _ParentRevenue =
    CALCULATE (
        [Total Revenue],
        REMOVEFILTERS ( dim_Customer[State] ),
        VALUES ( dim_Customer[Country] )
    )
VAR _DACH =
    CALCULATE ( [Total Revenue], dim_Customer[Country] IN { "DE", "AT", "CH" } )
VAR _RegionLabel =
    IF ( _Regions = 1, SELECTEDVALUE ( dim_Customer[State] ), _Regions & " regions" )
VAR _RegionVerb =
    IF ( _Regions = 1, " drives ", " drive " )
VAR _RegionScope =
    IF (
        _Markets = 1,
        SELECTEDVALUE ( dim_Customer[Country] ) & " revenue",
        "combined market revenue"
    )
VAR _CountryLabel =
    IF ( _Markets = 1, SELECTEDVALUE ( dim_Customer[Country] ), _Markets & " selected markets" )
VAR _CountryVerb =
    IF ( _Markets = 1, " drives ", " drive " )
RETURN
    SWITCH (
        TRUE (),
        [Region Filter Active] = 1,
            _RegionLabel & _RegionVerb
                & FORMAT ( DIVIDE ( [Total Revenue], _ParentRevenue ), "0%" )
                & " of " & _RegionScope,
        [Country Filter Active] = 1,
            _CountryLabel & _CountryVerb
                & FORMAT ( DIVIDE ( [Total Revenue], _GrandTotal ), "0%" )
                & " of total revenue",
        "Three markets drive "
            & FORMAT ( DIVIDE ( _DACH, [Total Revenue] ), "0%" )
            & " of revenue – DACH is the core dependency"
    )
```

```dax
Map Subtitle =
VAR _RevM =
    FORMAT ( DIVIDE ( [Total Revenue], 1000000 ), "0.0" )
RETURN
    SWITCH (
        TRUE (),
        [Region Filter Active] = 1, "Revenue by region (EUR " & _RevM & "M selected)",
        [Country Filter Active] = 1, "Revenue by country (EUR " & _RevM & "M selected)",
        "Revenue by country (EUR " & _RevM & "M total)"
    )
```

```dax
Market Ranking Title =
IF (
    [Region Filter Active] = 1 || [Country Filter Active] = 1,
    "Revenue and value per customer – current selection",
    "Growth comes from reach, not basket"
)
```

```dax
Market Ranking Subtitle =
VAR _Markets =
    DISTINCTCOUNT ( dim_Customer[Country] )
VAR _VPC =
    FORMAT ( DIVIDE ( [Total Revenue], [Total Customers] ), "€0" )
RETURN
    SWITCH (
        TRUE (),
        [Region Filter Active] = 1 || _Markets = 1, "Value per customer: " & _VPC,
        [Country Filter Active] = 1,
            "Ranked by revenue; value per customer clusters near " & _VPC
                & " across " & _Markets & " selected markets",
        "Ranked by revenue; value per customer clusters near " & _VPC & " across markets"
    )
```

```dax
Region Filter Active =
IF (
    CALCULATE ( ISFILTERED ( dim_Customer[State] ), ALLSELECTED ( ) ),
    1,
    0
)
```

```dax
Country Filter Active =
VAR _IsFiltered =
    CALCULATE ( ISFILTERED ( dim_Customer[Country] ), ALLSELECTED ( ) )
VAR _Visible =
    DISTINCTCOUNT ( dim_Customer[Country] )
VAR _All =
    CALCULATE ( DISTINCTCOUNT ( dim_Customer[Country] ), REMOVEFILTERS ( dim_Customer ) )
RETURN
    IF ( _IsFiltered && _Visible < _All, 1, 0 )
```

```dax
Country Total Revenue =
CALCULATE ( [Total Revenue], REMOVEFILTERS ( dim_Customer[State] ) )
```

```dax
Subtitle Revenue Trend =
VAR _SegVisible =
    DISTINCTCOUNT ( dim_Segment[Segment] )
VAR _SegAll =
    CALCULATE ( DISTINCTCOUNT ( dim_Segment[Segment] ), REMOVEFILTERS ( dim_Segment ) )
VAR _MktVisible =
    DISTINCTCOUNT ( dim_Customer[Country] )
VAR _MktAll =
    CALCULATE ( DISTINCTCOUNT ( dim_Customer[Country] ), REMOVEFILTERS ( dim_Customer ) )
VAR _SegText =
    IF ( _SegVisible < _SegAll, _SegVisible & " of " & _SegAll & " segments", "All segments" )
VAR _MktText =
    IF ( _MktVisible < _MktAll, _MktVisible & " of " & _MktAll & " markets", "all markets" )
RETURN
    _SegText & ", " & _MktText & " · Trailing 12M on right axis"
```

```dax
Subtitle Whatif Upside =
VAR _Rate =
    FORMAT ( [Reactivation Rate Value] / 100, "0%" )
RETURN
    "Gross recoverable revenue at " & _Rate & " reactivation. Gross of win-back discount – see methodology."
```

---

## Product, brand and category measures (Page 3)

After the single-direction refactor, the pre-aggregated views (`v_product_analytics`, `v_product_performance`, `v_brand_profitability`, `v_category_monthly_trend`) were removed from the model. Page 3 product, brand and category figures are now DAX measures (Folder 01), sourced from `dim_Product` as the axis or legend over the line-grain fact `v_items_for_bi` via `[Line Revenue]` and `[Line Margin %]`. See Folder 01 and the Data Model map above for the canonical definitions.

---

## Supporting Tables

### dim_Date – M-code Rolling Calendar

```m
let
    Source = #date(2023, 1, 1),
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
    #"Inserted Day Number" = Table.AddColumn(#"Inserted Day Name", "Day Number", each Date.DayOfWeek([Date], Day.Monday) + 1, Int64.Type),
    #"Added Year-Month-Number" = Table.AddColumn(#"Inserted Day Number", "Year-Month-Number", each [Year] * 100 + [Month], Int64.Type),
    #"Inserted Start of Month" = Table.AddColumn(#"Added Year-Month-Number", "Start of Month", each Date.StartOfMonth([Date]), type date),
    #"Inserted Start of Quarter" = Table.AddColumn(#"Inserted Start of Month", "Start of Quarter", each Date.StartOfQuarter([Date]), type date),
    #"Inserted Start of Year" = Table.AddColumn(#"Inserted Start of Quarter", "Start of Year", each Date.StartOfYear([Date]), type date),
    #"Reordered Columns" = Table.ReorderColumns(#"Inserted Start of Year",{"Date", "Year", "Month", "Month Name", "Year-Month", "Quarter", "Week of Year", "Day", "Day Name", "Year-Month-Number", "Day Number", "Start of Week", "Start of Month", "Start of Quarter", "Start of Year"})
in
    #"Reordered Columns"
```

After load: Mark as Date Table (Date column). Sort by Column: Month Name → Month. Sort by Column: Day Name → Day Number.

**Hierarchy – Calendar Drill:** `Start of Year` > `Start of Quarter` > `Start of Month` > `Start of Week` > `Date`. All `Start of *` levels are date-typed (`type date` in M, `UnderlyingDateTimeDataType = Date`), so drill levels render on a continuous axis. Built for the Page 3 category-trend line chart (#24), which sits at the `Start of Month` level. Replaces the former `Date Hierarchy` (`Date`, `Year-Month`), removed; its single consumer, a temporary Page 4 trend visual, was deleted in the same change.

**Calculated column `Is Closed Month`:** `EOMONTH ( dim_Date[Date], 0 ) <= MAX ( sales_curated[Order Date] )` – hidden, SummarizeBy=None, with a `///` description. TRUE for every day in a fully-elapsed month relative to the latest order date, FALSE for the current partial month. Applied as a visual-level filter (is True) on the Page 3 "Revenue Trend by Category" line chart so the category-trend ends on the last closed month, and reusable by Page 5 trend visuals. A DAX calculated column rather than an M column because it depends on the fact max date (row context on `dim_Date` does not propagate to `sales_curated`, so `MAX` returns the global max); consumed only by a report-layer visual filter, so it draws an accepted "Remove unnecessary columns" BPA flag (false-positive – BPA cannot see the report-layer reference).

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

**Note:** `dim_Segment` is a static DAX DATATABLE (no Power Query) that merges the former `dim_SegmentOrder` (sort order + color) and `dim_SegmentActions` (CRM attributes: email cadence, loyalty tier, discount approach, budget allocation) into one 7-column dimension, per the single-direction refactor. `SortOrder` is hidden; `Segment` is the displayed key, sorted by `SortOrder`.

**Note:** the recommended-action column is not held here – it lives on `dim_Customer` (SQL: `recommended_action AS action`), the customer-grain dimension. No duplication.

### dim_KPI_Selector – DAX DATATABLE

```dax
dim_KPI_Selector =
DATATABLE (
    "KPI", STRING,
    "SortOrder", INTEGER,
    {
        { "Total Revenue", 1 },
        { "Total Customers", 2 },
        { "Average Order Value", 3 },
        { "Average Recency Days", 4 },
        { "Revenue at Risk", 5 }
    }
)
```

After load: Sort by Column: KPI → SortOrder. **Disconnected** – no relationship to any table; drives `[Dynamic KPI Selector]` and `[Dynamic KPI Label]` via `SELECTEDVALUE`.

### Reactivation Rate – What-If Parameter

Modeling → New Parameter → Name: Reactivation Rate, Min: 0, Max: 50, Increment: 5, Default: 10.

---

## Relationships

The authoritative relationship list is the **Active relationships (7)** table in the Data Model section above (after the single-direction refactor and the date-join addition: 7 active, all M:1 single-direction, 0 bidirectional). It is not duplicated here, to avoid drift.

**Disconnected / standalone:** `dim_KPI_Selector` is a disconnected slicer (no relationship).

### Fact-to-fact joins: explicitly NOT used

The auto-detected inactive relationship `v_items_for_bi[Order ID] → sales_curated[Order ID]` was removed. The model now has **zero inactive relationships**. The deliberate design choice – consistent with Kimball star-schema discipline and the dual-grain architecture – is that fact tables never join directly to other fact tables. Instead:

- **Cross-fact filter propagation** flows through shared dimensions (`dim_Customer`, `dim_Product`, `dim_Date`)
- **Order-grain ↔ line-grain reconciliation** is done via measure math, not a relationship. The `[Grain Reconciliation]` measure computes `[Total Revenue] − [Line Revenue]` and is invariant at zero. If it ever drifts from zero, the dimension-mediated join has broken – that's the signal, not a relationship line in the model
- **USERELATIONSHIP**: no DAX expression in the model uses `USERELATIONSHIP()` to activate a fact-to-fact join. The removed `Order ID` relationship had zero callers, confirming the inactive-and-unused pattern that BPA flags

**BPA delta:** "Inactive relationships that are never activated" rule 1 → 0 violations.

---

## Total: 109 measures – 108 across 6 display folders + 1 What-If parameter measure (`Reactivation Rate Value`). The `RFM Score Selector` field parameter is a table, not a measure. No redundant calculations.

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

**Note:** the three score columns this Field Parameter references (`R Score`, `F Score`, `M Score`) live on `dim_Customer`. `M Score` is hidden – part of the RFM analytic payload merged from the former `v_rfm_for_bi` satellite; `R Score` and `F Score` are now visible (draggable score axes for the Page 5 RFM heatmap). Field parameters resolve source columns regardless of visibility, so the slicer works while the hidden `M Score` stays out of the Fields pane (see Model Hygiene → Foreign Key & Surrogate Key Visibility).
