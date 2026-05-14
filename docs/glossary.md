# Glossary

Domain and technical terms used across the project.

| Term | Meaning |
|---|---|
| **AOV** | Average Order Value – total revenue divided by order count. |
| **ARG_MAX** | Aggregate returning the value of one column at the row where another column is maximum. Useful for "value at most recent row" patterns. |
| **CLV** | Customer Lifetime Value – total expected revenue from a customer over their full relationship with the brand. |
| **Composite RFM score** | Sum of `r_score + f_score + m_score`, ranging from 3 (worst) to 15 (best). |
| **Conformed dimension** | A dimension whose attributes mean the same thing across multiple fact tables, enabling consistent cross-fact analysis. |
| **DirectQuery** | Power BI mode that issues live queries against the source on every interaction. Not used here – Import mode chosen for sub-second response and reliable hosting; the dual-grain SQL design supports DirectQuery should it be needed in production. |
| **Grain (fact)** | The level of detail captured by a row in a fact table. Order-grain = one row per order. Line-grain = one row per line item. |
| **Idempotent** | A SQL script that produces the same end state regardless of how many times it is run. Achieved here via `CREATE OR REPLACE`. |
| **Import mode** | Power BI mode that loads data into the model file at refresh time. Used here for fast interactivity. |
| **Kimball dimensional model** | A star-schema approach to data warehousing with denormalised dimensions and central fact tables. See [ADR 0004](adr/0004-star-schema-with-conformed-dimensions.md). |
| **`NTILE(n)`** | SQL window function dividing rows into n approximately equal-sized buckets, useful for percentile-based segmentation. See [ADR 0006](adr/0006-rfm-segmentation-with-ntile.md). |
| **Quintile** | One-fifth slice of a distribution; the bucket produced by `NTILE(5)`. |
| **Recency anchor** | The reference date from which "days since last order" is measured. This project uses `MAX(OrderDate)` rather than `CURRENT_DATE()`, so segmentation is reproducible on the bounded historical dataset. |
| **RFM** | Recency, Frequency, Monetary – a customer segmentation framework based on observed transaction behaviour. |
| **Sharding (BigQuery)** | Splitting a logical table across many physically-named tables (`orders202301`, `orders202302`, ...). BigQuery scans them via wildcard syntax (`orders20*`). |
| **`sales_curated`** | The order-grain curated fact table (~169K rows) used by five of the six Power BI pages. See [ADR 0005](adr/0005-dual-grain-fact-model.md). |
| **Star schema** | Database design with central fact tables surrounded by dimension tables, enabling simple SQL joins and fast aggregation. |
| **`v_items_for_bi`** | The line-grain BI view (~275K rows) used by the Product page. |
| **Weighted margin** | `SUM(profit) / SUM(revenue)`, contrasted with `AVG(margin_per_order)` which double-weights small orders. See [ADR 0007](adr/0007-two-tier-margin-calculation.md). |
| **What-If parameter** | A Power BI feature for interactive scenario modelling (e.g., simulating a reactivation success rate). |
