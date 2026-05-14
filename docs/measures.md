# DAX Measures Reference
## Kupferkanne – 36 Measures in 6 Folders + 3 Subtitle Measures + Field Parameter
### Author: Ryszard Twardy
### v6 (2026-04-24) – sales_curated import, [Total Revenue]/[Total Profit] refactored to fact-grain, +7 Page 3 measures, +Subtitle Page N convention

> Source of truth for all DAX measures. Every table and column name verified against BigQuery SQL scripts (03_rfm_pipeline, 05_analytics_marts). **Since dual-grain D026 (2026-05-07)**, Power BI imports `sales_curated` (order-grain fact table from script 03_rfm_pipeline) as the primary fact source. `v_rfm_for_bi` retained for Customer-grain analytics only.

---

## Data Model: Table → SQL Source Mapping

| Power BI Table | BigQuery Object | Granularity | Key Columns |
|---|---|---|---|
| **sales_curated** | `sales_curated` (TABLE) | **1 row per order (~169K)** | OrderID, CustomerID, OrderDate, OrderValue, OrderCost, OrderProfit, OrderMarginPct, Country, DominantCategory, DominantBrand |
| **v_items_for_bi** | `v_items_for_bi` (VIEW) | **1 row per order line (~275K)** | OrderID, ProductID, CustomerID, OrderDate, Quantity, UnitPrice, LineNetAmount, LineCost, LineProfit, Brand, ProductCategory |
| v_rfm_for_bi | `v_rfm_for_bi` (VIEW) | 1 row per customer | customer_id, total_spend, order_count, recency_days, r/f/m_score, health_score, segment |
| v_product_analytics | `v_product_analytics` (VIEW) | 1 row per order×product | OrderID, ProductID, LineRevenue, LineProfit, Quantity |
| v_dim_customers_std | `v_dim_customers_std` (VIEW) | 1 row per customer | CustomerID, FullName, Email, Phone |
| v_dim_products_std | `v_dim_products_std` (VIEW) | 1 row per product | ProductID, ProductName, Brand, MarginPct |
| v_monthly_revenue | `v_monthly_revenue` (VIEW) | 1 row per month | order_month, total_revenue, total_profit |
| v_product_performance | `v_product_performance` (VIEW) | 1 row per product | Product ID, Product Name, Product Category, total_revenue |
| v_brand_profitability | `v_brand_profitability` (VIEW) | 1 row per brand | Brand, total_revenue, brand_margin_pct |
| v_regional_performance | `v_regional_performance` (VIEW) | 1 row per country/state/city | Country, total_revenue, arpu |
| v_category_monthly_trend | `v_category_monthly_trend` (VIEW) | 1 row per category×brand×month | Product Category, category_revenue |
| v_country_summary | `v_country_summary` (VIEW) | 1 row per country | Country, revenue, profit, arpu |
| dim_Date | DAX CALENDAR | 1 row per day | Date, Year, Month, Year-Month |
| dim_SegmentOrder | DAX DATATABLE | 6 rows | Segment, SortOrder, SegmentColor |
| dim_KPI_Selector | DAX DATATABLE | 5 rows | KPI Name (disconnected) |
| dim_SegmentActions | Enter Data | 6 rows | Segment, Email Cadence, Loyalty Tier, Discount Approach, Budget Allocation, SortOrder |
| Reactivation Rate | What-If Parameter | auto-generated | Reactivation Rate Value (0–50, step 5) |

**v6 architecture rule (R026):** `[Total Revenue]` and `[Total Profit]` measures pull from fact-grain `sales_curated` ONLY. Dimensional views serve as drill-down axes/legends only – pre-aggregated views break filter context across products/brands/categories.

**Active relationships (8):**
- sales_curated[CustomerID] ↔ dim_customers[CustomerID] | M:1 | Single
- sales_curated[ProductID] ↔ dim_products[ProductID] | M:1 | Single
- sales_curated[OrderDate] ↔ dim_Date[Date] | M:1 | Single
- v_rfm_for_bi[CustomerID] ↔ dim_customers[CustomerID] | M:1 | Single
- dim_SegmentActions[Segment] ↔ dim_SegmentOrder[Segment] | 1:1 | Both
- (3 additional from v5 retained)

---

## Folder: 01 – Core KPIs

| # | Measure | Formula | Format | Pages |
|---|---|---|---|---|
| 1 | Total Revenue | `SUM(sales_curated[LineNetAmount])` | € Currency (€ DE), 2dp, display Millions | 1, 2, 3, 4 |
| 2 | Total Customers | `COUNTROWS(v_rfm_for_bi)` | # 0dp | 1, 2 |
| 3 | Total Orders | `SUM(v_rfm_for_bi[order_count])` | # 0dp | 1 |
| 4 | Avg Order Value | `DIVIDE([Total Revenue], [Total Orders], 0)` | € Currency, 2dp | 1 |
| 5 | Avg Customer LTV | `DIVIDE([Total Revenue], [Total Customers], 0)` | € Currency, 0dp | 1 |
| 6 | Avg Recency Days | `AVERAGE(v_rfm_for_bi[recency_days])` | Custom `#,##0 "days"` | 1, 2 |
| 7 | Avg Frequency | `AVERAGE(v_rfm_for_bi[order_count])` | Dec 1dp | 2 |
| 8 | Avg Monetary | `AVERAGE(v_rfm_for_bi[total_spend])` | € Currency, 2dp | 2 |
| 25 | Distinct Orders | `DISTINCTCOUNT(v_product_analytics[OrderID])` | # 0dp | 3 |
| 26 | Total Profit | `SUM(sales_curated[LineProfit])` | € Currency (€ DE), 2dp, display Millions | 1, 3, 4 |
| 27 | Profit Margin % | `DIVIDE([Total Profit], [Total Revenue], 0)` | % 2dp | 1, 3 |
| **30** | **Total Products (v6)** | `DISTINCTCOUNT(v_product_performance[Product ID])` | # 0dp | 3 |
| **31** | **Total Brands (v6)** | `DISTINCTCOUNT(v_brand_profitability[Brand])` | # 0dp | 3 |
| **32** | **Top Brand Revenue (v6)** | `MAXX(VALUES(v_brand_profitability[Brand]), [Total Revenue])` | € Currency, display Millions | 3 |
| **33** | **Top Brand Name (v6)** | VAR pattern – see formula block below | Text | 3 |
| **34** | **Avg Brand Margin % (v6)** | `AVERAGEX(VALUES(v_brand_profitability[Brand]), DIVIDE([Total Profit], [Total Revenue]))` | % 2dp | 3 |
| **35** | **Top Category Revenue (v6)** | `MAXX(VALUES(v_product_performance[Product Category]), [Total Revenue])` | € Currency, display Millions | 3 |
| **36** | **Top Category Name (v6)** | VAR pattern – see formula block below | Text | 3 |

**Weighted margin principle (R008):** `Profit Margin %` uses `SUM(profit) / SUM(revenue)`, never `AVERAGE(margin_pct)`. Arithmetic mean of percentages misrepresents aggregate when orders have different sizes.

**Equal-weight benchmark (R025, NEW v6):** `Avg Brand Margin %` uses `AVERAGEX` over brands – equal-weight semantic for benchmarking, NOT P&L. Returns 51.88% vs `Profit Margin %` 59.78%. Both legitimate, qualifying labels mandatory in UI ("Average Brand Margin", never "Margin").

**Fact-grain principle (R026 + R028 dual-grain naming):** measures #1 (Total Revenue) and #26 (Total Profit) refactored to source from `sales_curated` (order-grain fact table). Dimensional views serve as drill-down axes/legends only.

### Top Brand Name / Top Category Name – full formula

```dax
Top Brand Name = 
VAR maxRev = [Top Brand Revenue]
RETURN
    CALCULATE(
        MAX(v_brand_profitability[Brand]),
        FILTER(
            VALUES(v_brand_profitability[Brand]),
            [Total Revenue] = maxRev
        )
    )

Top Category Name = 
VAR maxRev = [Top Category Revenue]
RETURN
    CALCULATE(
        MAX(v_product_performance[Product Category]),
        FILTER(
            VALUES(v_product_performance[Product Category]),
            [Total Revenue] = maxRev
        )
    )
```

**Edge case:** ties in revenue resolve alphabetically last (MAX text ordering). Acceptable for KPI cards – display only.

---

## Folder: 02 – RFM Scores

| # | Measure | Formula | Format | Pages |
|---|---|---|---|---|
| 9 | Avg R Score | `AVERAGE(v_rfm_for_bi[r_score])` | Dec 1dp | 2, 6 |
| 10 | Avg F Score | `AVERAGE(v_rfm_for_bi[f_score])` | Dec 1dp | 2, 6 |
| 11 | Avg M Score | `AVERAGE(v_rfm_for_bi[m_score])` | Dec 1dp | 2, 6 |
| 12 | Avg Health Score | `AVERAGE(v_rfm_for_bi[health_score])` | Dec 1dp | 1, 2, 4 |

---

## Folder: 03 – Segment Analysis

| # | Measure | Format | Pages |
|---|---|---|---|
| 13 | Segment % of Total | % 1dp | 1, 2 |
| 14 | Revenue % of Total | % 1dp | 2 |
| 15 | Revenue at Risk | € 0dp | 1, 4 |

```dax
Segment % of Total =
VAR SegmentCount = COUNTROWS(v_rfm_for_bi)
VAR TotalCount =
    CALCULATE(
        COUNTROWS(v_rfm_for_bi),
        ALL(v_rfm_for_bi)
    )
RETURN
DIVIDE(SegmentCount, TotalCount, 0)
```

```dax
Revenue % of Total =
VAR SegmentRevenue = SUM(v_rfm_for_bi[total_spend])
VAR TotalRevenue =
    CALCULATE(
        SUM(v_rfm_for_bi[total_spend]),
        ALL(v_rfm_for_bi)
    )
RETURN
DIVIDE(SegmentRevenue, TotalRevenue, 0)
```

```dax
Revenue at Risk =
CALCULATE(
    SUM(v_rfm_for_bi[total_spend]),
    v_rfm_for_bi[segment] IN {"At Risk", "Hibernating"}
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
    SUM(v_rfm_for_bi[total_spend]),
    v_rfm_for_bi[recency_days] <= 90
)

Revenue Cooling =
CALCULATE(
    SUM(v_rfm_for_bi[total_spend]),
    v_rfm_for_bi[recency_days] > 90
        && v_rfm_for_bi[recency_days] <= 180
)

Revenue Dormant =
CALCULATE(
    SUM(v_rfm_for_bi[total_spend]),
    v_rfm_for_bi[recency_days] > 180
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
        SUM(v_rfm_for_bi[total_spend]),
        v_rfm_for_bi[segment] IN {"At Risk", "Hibernating"}
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
VAR Score = AVERAGE(v_rfm_for_bi[health_score])
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
    SUM(v_rfm_for_bi[total_spend]),
    COUNTROWS(v_rfm_for_bi),
    0
)
```

```dax
Country Revenue Share =
DIVIDE(
    SUM(v_rfm_for_bi[total_spend]),
    CALCULATE(
        SUM(v_rfm_for_bi[total_spend]),
        ALL(v_rfm_for_bi)
    ),
    0
)
```

```dax
Segment Color =
SWITCH(
    SELECTEDVALUE(v_rfm_for_bi[segment]),
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

## Product Measures (No folder – used directly from v_product_analytics)

These are not DAX measures. Page 3 visuals pull directly from **v_product_analytics** columns and **pre-aggregated views** (v_product_performance, v_brand_profitability, v_category_monthly_trend). The columns are:

| Source Table | Column | Display Name | Used On |
|---|---|---|---|
| v_product_analytics | LineRevenue | Line Revenue | 3 |
| v_product_analytics | LineProfit | Line Profit | 3 |
| v_product_analytics | Quantity | Quantity | 3 |
| v_product_analytics | OrderID | – (DISTINCTCOUNT for order counts) | 3 |
| v_product_performance | total_revenue | Total Revenue | 3 |
| v_product_performance | revenue_rank | Revenue Rank | 3 |
| v_brand_profitability | brand_margin_pct | Brand Margin % | 3 |
| v_brand_profitability | revenue_share | Revenue Share | 3 |

**DAX tip:** For product-filtered order counts, use `DISTINCTCOUNT(v_product_analytics[OrderID])`, not `[Total Orders]`. The dim_products filter propagates through v_product_analytics but not through v_rfm_for_bi.

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
DATATABLE(
    "Segment", STRING,
    "SortOrder", INTEGER,
    "SegmentColor", STRING,
    {
        {"Champions", 1, "#4A7AA0"},
        {"Loyal Customers", 2, "#7BA8B8"},
        {"Potential Loyalists", 3, "#8FA87E"},
        {"Recent Customers", 4, "#D4A762"},
        {"At Risk", 5, "#A05A55"},
        {"Hibernating", 6, "#A5A29A"}
    }
)
```

After load: Sort by Column: Segment → SortOrder. Relationship: v_rfm_for_bi[segment] → dim_SegmentOrder[Segment] (Many:1).

**Note:** ActionPriority is NOT included here. The `action` column already exists in v_rfm_for_bi (from SQL: `recommended_action AS action`). No duplication needed.

### dim_KPI_Selector – Enter Data

5 rows, 1 column (`KPI Name`): Total Revenue, Total Customers, Avg Order Value, Avg Recency, Revenue at Risk. **Disconnected** – no relationship to any table.

### Reactivation Rate – What-If Parameter

Modeling → New Parameter → Name: Reactivation Rate, Min: 0, Max: 50, Increment: 5, Default: 10.

---

## Relationships (5 total)

| From | To | Cardinality | Cross-filter |
|---|---|---|---|
| v_rfm_for_bi[last_order_date] | dim_Date[Date] | Many:1 | Single |
| v_rfm_for_bi[segment] | dim_SegmentOrder[Segment] | Many:1 | Single |
| v_rfm_for_bi[customer_id] | v_dim_customers_std[CustomerID] | Many:1 | Single |
| v_product_analytics[OrderDate] | dim_Date[Date] | Many:1 | Single |
| v_product_analytics[ProductID] | v_dim_products_std[ProductID] | Many:1 | Single |

**No relationship** between v_rfm_for_bi and v_product_analytics (different granularity). No relationship for dim_KPI_Selector (disconnected slicer). Pre-aggregated views (v_monthly_revenue, v_brand_profitability, etc.) have **no relationships** – they are standalone tables used directly on specific pages.

---

## Total: 29 measures in 6 display folders + 1 Field Parameter. No orphans. No redundant calculations.

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

---

## Changelog

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
