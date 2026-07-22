# Data Model

A Kimball-style dimensional model with two conformed dimensions and two fact tables sharded by month, plus a dual-grain semantic layer for Power BI consumption. Architectural rationale lives in [ADR 0004](adr/0004-star-schema-with-conformed-dimensions.md) (schema choice) and [ADR 0005](adr/0005-dual-grain-fact-model.md) (dual-grain design).

## Star schema

```mermaid
erDiagram
    dim_customers ||--o{ orders : "places"
    dim_products ||--o{ items : "appears in"
    orders ||--|{ items : "contains"

    dim_customers {
        int64 CustomerID PK
        string FirstName
        string LastName
        string Country
        string City
        date SignupDate
    }
    dim_products {
        string ProductID PK
        string ProductName
        string Brand
        string ProductCategory
        float UnitCost
    }
    orders {
        int64 OrderID PK
        int64 CustomerID FK
        date OrderDate
        float OrderValue
        float OrderProfit
        string Country
    }
    items {
        int64 OrderID FK
        string ProductID FK
        int Quantity
        float UnitPrice
        float LineNetAmount
    }
```

## Tables

### Dimensions

| Table | Rows | Purpose |
|---|---|---|
| `dim_customers` | ~15,000 | Customer master with country, city, signup date |
| `dim_products` | 60 | Product catalogue across 5 brands and 6 categories |

### Facts (sharded by month, Jan 2023 – Mar 2026)

| Pattern | Total rows | Grain | Purpose |
|---|---|---|---|
| `orders20YYMM` | ~170,000 across 39 shards | Order | Header-level transactions |
| `items20YYMM` | ~275,000 across 39 shards | Line item | Product-level detail |

Sharding by month allows BigQuery to prune scans when querying date ranges. Single-month queries hit one shard; cross-period queries use wildcard tables (`orders20*`).

## BI semantic layer

Two curated fact objects feed Power BI, each at a different grain:

| Object | Grain | Rows | Used by PBI pages |
|---|---|---|---|
| `sales_curated` | Order | ~169K | 1 Executive Summary, 2 Segment Deep Dive, 4 Churn Risk & What-If, 5 Customer Lifecycle Intelligence, 6 Regional Analysis, 7 Customer Drillthrough |
| `v_items_for_bi` | Line item | ~275K | 3 Product & Brand |

The dual-grain approach prevents aggregation errors that would arise from joining order-level and line-level metrics in a single fact table. Power BI measures follow a naming convention: `[Total *]` for order-grain measures and `[Line *]` for line-grain, enforcing clarity at consumption time. See [measures.md](measures.md) for the full catalogue.

### Standalone analytical views

Two pre-aggregated views feed specific Page 5 visuals. Each is imported standalone: it carries its own grain and stays outside the star schema, apart from the single calendar join noted below.

| Object | Grain | Columns | Used by |
|---|---|---|---|
| `v_revenue_new_returning` | One row per month per customer type (~77: 39 New + 38 Returning) | Revenue Month (date), Customer Type (text), Revenue (EUR), Active Customers (int) | Page 5 New vs Returning area chart |
| `v_cohort_retention` | One row per acquisition cohort per tenure month (cohort month by months since acquisition) | Cohort Month (date), Months Since Acquisition (int), Active Customers (int), Cohort Customers (int), Retention Rate (percent) | Page 5 Cohort Retention heatmap |

`v_revenue_new_returning` joins the date dimension on `Revenue Month` to `dim_Date[Date]` (many-to-one, single-direction), so the calendar slicer and the closed-month trim reach it. `v_cohort_retention` is deliberately left unrelated to the calendar: its grain is cohort-by-tenure rather than a point in time, so it is sliced only by its own axes.

### Semantic model topology

The Power BI semantic model as built, complementing the warehouse star above. Its customer dimension `dim_Customer` sources the BI customer view (`v_dim_customers_for_bi`, built in step 04_5), which carries the RFM scores and segment assignment alongside the customer master, so segmentation lives on the customer dimension itself (ADR 0012) rather than a snowflaked table. Segment display attributes are factored into a small conformed dimension, `dim_Segment` (the six RFM segments with their palette colours), per ADR 0013.

This is where the model intentionally diverges from the warehouse star above: geography (`Country`) is carried on `dim_Customer`, not on the order fact, and there is no fact-to-fact (order-to-item) relationship – the two grains join only through shared conformed dimensions. All seven relationships are many-to-one with single-direction cross-filtering (filters propagate dimension to fact); there are zero bidirectional and zero inactive relationships.

The topology splits into two views around the conformed dimensions `dim_Customer` and `dim_Date`, which are shared across both grains.

**Order-grain fact and the standalone monthly view:**

```mermaid
erDiagram
    dim_Segment ||--o{ dim_Customer : "Segment"
    dim_Customer ||--o{ sales_curated : "Customer ID"
    dim_Date ||--o{ sales_curated : "Order Date"
    dim_Date ||--o{ v_revenue_new_returning : "Revenue Month"
```

**Line-grain star:**

```mermaid
erDiagram
    dim_Customer ||--o{ v_items_for_bi : "Customer ID"
    dim_Product ||--o{ v_items_for_bi : "Product ID"
    dim_Date ||--o{ v_items_for_bi : "Order Date"
```

**Active relationships (7 – all M:1, single-direction):**

| # | Relationship (FK -> PK) | Cardinality | Cross-filter | Purpose |
|---|---|---|---|---|
| 1 | `sales_curated[Customer ID] -> dim_Customer[Customer ID]` | M:1 | Single | Order-grain fact to customer dimension |
| 2 | `sales_curated[Order Date] -> dim_Date[Date]` | M:1 | Single | Order-grain fact to calendar |
| 3 | `v_items_for_bi[Customer ID] -> dim_Customer[Customer ID]` | M:1 | Single | Line-grain fact to customer dimension |
| 4 | `v_items_for_bi[Product ID] -> dim_Product[Product ID]` | M:1 | Single | Line-grain fact to product dimension |
| 5 | `v_items_for_bi[Order Date] -> dim_Date[Date]` | M:1 | Single | Line-grain fact to calendar; date-slices the `[Line *]` measures and the Page 3 Product & Brand trend |
| 6 | `dim_Customer[Segment] -> dim_Segment[Segment]` | M:1 | Single | Segment attribution onto the merged segment dimension |
| 7 | `v_revenue_new_returning[Revenue Month] -> dim_Date[Date]` | M:1 | Single | Monthly calendar slice for the Page 5 New vs Returning area chart |

Five model tables carry no relationship: `dim_KPI_Selector` (disconnected KPI slicer), `RFM Score Selector` (field parameter over `dim_Customer[R/F/M Score]`), `Reactivation Rate` (What-If parameter), `_Measures` (hidden measures host), and `v_cohort_retention` (standalone analytical view backing the Page 5 cohort retention heatmap). Seven related plus five unrelated is twelve model tables.

## Naming conventions

- Raw source tables (`dim_customers`, `dim_products`, `orders20*`, `items20*`): original PascalCase headers preserved (`CustomerID`, `OrderDate`, `LineNetAmount`); raw shapes are never edited in place.
- Curated layer (standardisation views, staging, and everything downstream): `snake_case` columns (`customer_id`, `order_date`, `line_net_amount`). The casing flip happens exactly once, at the standardisation/staging boundary (`v_dim_*_std`, `stg_*` intake).
- BigQuery tables and views: `snake_case` names.
- Power BI: imported columns are remapped at the consumption point (Power Query `Table.RenameColumns`) to Title Case with spaces for multi-word labels (`Order Value`) and `Customer ID`-style for IDs. Measures: Title Case.
- Identifiers are verbatim within each layer across SQL → M remap → DAX → documentation. No abbreviation drift.

## Schema contract

`v_dim_customers_std` and `v_dim_products_std` (created in step 00_1) act as a semantic contract layer. All downstream SQL references these standardisation views rather than the raw `dim_*` tables. If upstream raw schema changes, only the standardisation views need adjustment – analytical SQL is isolated from raw-shape concerns.

## Customer segmentation table

`rfm_customer_segments` (created in step 03) stores per-customer scoring:

| Field | Type | Source |
|---|---|---|
| `customer_id` | STRING | Joined to `dim_customers` |
| `r_score`, `f_score`, `m_score` | INT64 | `NTILE(5)` per dimension |
| `rfm_total_score` | INT64 | Sum 3–15 |
| `rfm_segment` | STRING | Champions, Loyal Customers, Potential Loyalists, Recent Customers, At Risk, Hibernating |
| `recommended_action` | STRING | Mapped from segment band |

See [methodology.md](methodology.md) for the RFM scoring logic and [ADR 0006](adr/0006-rfm-segmentation-with-ntile.md) for the choice of NTILE-based scoring.
