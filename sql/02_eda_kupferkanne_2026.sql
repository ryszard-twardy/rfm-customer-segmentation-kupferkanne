-- =============================================================================
-- 02_eda_kupferkanne_2026.sql
-- Exploratory Data Analysis layer
--
-- Purpose:   Eight foundational EDA views on cleaned staging data, designed
--            to inform RFM segmentation design decisions in step 03.
--
-- Inputs:    stg_orders_validated, stg_items_validated (from step 01_0)
-- Outputs:   8 views in `kupferkanne-2026.sales`, prefix `eda_`
--
-- Design:    Idempotent (CREATE OR REPLACE). View definitions select only
--            columns needed for each exploratory question to keep BQ scans
--            tight. Each view answers ONE question; composition happens in
--            downstream consumers.
--
-- See ADR-0003 (pipeline order: EDA before transform).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. eda_order_value_distribution
-- -----------------------------------------------------------------------------
-- Purpose:   Percentile distribution of OrderValue to understand the spread of
--            transaction sizes. Informs Monetary dimension binning in RFM.
-- Reading:   Q10/Q25/Q50/Q75/Q90/Q99 give the shape of the distribution. A
--            large gap between P90 and P99 indicates a long tail (whales).
-- -----------------------------------------------------------------------------

CREATE OR REPLACE VIEW `kupferkanne-2026.sales.eda_order_value_distribution` AS
SELECT
    APPROX_QUANTILES(OrderValue, 100)[OFFSET(10)] AS p10,
    APPROX_QUANTILES(OrderValue, 100)[OFFSET(25)] AS p25,
    APPROX_QUANTILES(OrderValue, 100)[OFFSET(50)] AS median,
    APPROX_QUANTILES(OrderValue, 100)[OFFSET(75)] AS p75,
    APPROX_QUANTILES(OrderValue, 100)[OFFSET(90)] AS p90,
    APPROX_QUANTILES(OrderValue, 100)[OFFSET(99)] AS p99,
    MIN(OrderValue) AS min_value,
    MAX(OrderValue) AS max_value,
    ROUND(AVG(OrderValue), 2) AS mean_value,
    COUNT(*) AS order_count
FROM `kupferkanne-2026.sales.stg_orders_validated`;

-- -----------------------------------------------------------------------------
-- 2. eda_order_value_outliers
-- -----------------------------------------------------------------------------
-- Purpose:   Flag orders above the 99th percentile threshold. These may be
--            data entry errors, B2B bulk orders, or legitimate high-value
--            transactions.
-- Reading:   Review outliers for plausibility. If artifacts, address in the
--            cleaning layer. If legitimate, ensure RFM Monetary captures them.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW `kupferkanne-2026.sales.eda_order_value_outliers` AS
WITH p99_threshold AS (
    SELECT APPROX_QUANTILES(OrderValue, 100)[OFFSET(99)] AS p99
    FROM `kupferkanne-2026.sales.stg_orders_validated`
)

SELECT
    o.OrderID,
    o.CustomerID,
    o.OrderDate,
    o.Country,
    o.OrderValue,
    p.p99 AS p99_threshold,
    ROUND(o.OrderValue / p.p99, 2) AS multiple_of_p99
FROM `kupferkanne-2026.sales.stg_orders_validated` AS o
CROSS JOIN p99_threshold AS p
WHERE o.OrderValue > p.p99
ORDER BY o.OrderValue DESC;

-- -----------------------------------------------------------------------------
-- 3. eda_country_breakdown
-- -----------------------------------------------------------------------------
-- Purpose:   Order volume and average order value per country. Reveals market
--            concentration and country-level AOV variation.
-- Reading:   Identifies dominant markets by volume and high-value markets by
--            AOV. Used to inform Regional dashboard page and filter design.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW `kupferkanne-2026.sales.eda_country_breakdown` AS
WITH total_revenue AS (
    SELECT SUM(OrderValue) AS grand_total
    FROM `kupferkanne-2026.sales.stg_orders_validated`
)

SELECT
    o.Country,
    COUNT(*) AS order_count,
    COUNT(DISTINCT o.CustomerID) AS customer_count,
    ROUND(AVG(o.OrderValue), 2) AS avg_order_value,
    ROUND(SUM(o.OrderValue), 2) AS total_revenue,
    ROUND(SUM(o.OrderValue) * 100.0 / t.grand_total, 2) AS revenue_share_pct
FROM `kupferkanne-2026.sales.stg_orders_validated` AS o
CROSS JOIN total_revenue AS t
GROUP BY o.Country, t.grand_total
ORDER BY total_revenue DESC;

-- -----------------------------------------------------------------------------
-- 4. eda_monthly_temporal_pattern
-- -----------------------------------------------------------------------------
-- Purpose:   Monthly order volume and revenue trend. Identifies seasonality,
--            growth trajectory, and data quality gaps (missing months).
-- Reading:   Look for seasonal patterns (e.g., Q4 lift), level shifts in
--            recent months, and unexpected gaps.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW `kupferkanne-2026.sales.eda_monthly_temporal_pattern` AS
SELECT
    FORMAT_DATE('%Y-%m', OrderDate) AS year_month,
    COUNT(*) AS order_count,
    COUNT(DISTINCT CustomerID) AS active_customers,
    ROUND(SUM(OrderValue), 2) AS monthly_revenue,
    ROUND(AVG(OrderValue), 2) AS avg_order_value
FROM `kupferkanne-2026.sales.stg_orders_validated`
GROUP BY year_month
ORDER BY year_month;

-- -----------------------------------------------------------------------------
-- 5. eda_customer_frequency_distribution
-- -----------------------------------------------------------------------------
-- Purpose:   Distribution of order counts per customer. Validates whether the
--            RFM Frequency dimension has enough spread for NTILE(5).
-- Reading:   If 80%+ of customers have exactly 1 order, Frequency loses
--            signal. If spread is healthy, NTILE quintiles separate cleanly.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW `kupferkanne-2026.sales.eda_customer_frequency_distribution` AS
WITH customer_orders AS (
    SELECT
        CustomerID,
        COUNT(*) AS order_count
    FROM `kupferkanne-2026.sales.stg_orders_validated`
    GROUP BY CustomerID
),

total_customers AS (
    SELECT COUNT(DISTINCT CustomerID) AS grand_total
    FROM `kupferkanne-2026.sales.stg_orders_validated`
)

SELECT
    co.order_count,
    COUNT(*) AS customers_with_this_count,
    ROUND(COUNT(*) * 100.0 / tc.grand_total, 2) AS pct_of_customers
FROM customer_orders AS co
CROSS JOIN total_customers AS tc
GROUP BY co.order_count, tc.grand_total
ORDER BY co.order_count;

-- -----------------------------------------------------------------------------
-- 6. eda_recency_distribution
-- -----------------------------------------------------------------------------
-- Purpose:   Days since each customer's most recent order, anchored on the
--            dataset's MAX(OrderDate). Validates the recency anchor choice.
-- Reading:   Using CURRENT_DATE() instead would inflate recency uniformly
--            (the dataset ends in the past). MAX(OrderDate) preserves the
--            true recency distribution. See ADR-0006 for full rationale.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW `kupferkanne-2026.sales.eda_recency_distribution` AS
WITH anchor AS (
    SELECT MAX(OrderDate) AS data_as_of_date
    FROM `kupferkanne-2026.sales.stg_orders_validated`
),

customer_recency AS (
    SELECT
        o.CustomerID,
        MAX(o.OrderDate) AS last_order_date,
        DATE_DIFF(a.data_as_of_date, MAX(o.OrderDate), DAY) AS days_since_last_order
    FROM `kupferkanne-2026.sales.stg_orders_validated` AS o
    CROSS JOIN anchor AS a
    GROUP BY o.CustomerID, a.data_as_of_date
)

SELECT
    CASE
        WHEN days_since_last_order < 30 THEN '01_active_30d'
        WHEN days_since_last_order < 90 THEN '02_recent_90d'
        WHEN days_since_last_order < 180 THEN '03_warming_180d'
        WHEN days_since_last_order < 365 THEN '04_cooling_365d'
        WHEN days_since_last_order < 730 THEN '05_cold_2y'
        ELSE '06_dormant_2y_plus'
    END AS recency_bucket,
    COUNT(*) AS customer_count,
    MIN(days_since_last_order) AS min_days,
    MAX(days_since_last_order) AS max_days
FROM customer_recency
GROUP BY recency_bucket
ORDER BY recency_bucket;

-- -----------------------------------------------------------------------------
-- 7. eda_pareto_concentration
-- -----------------------------------------------------------------------------
-- Purpose:   Revenue share contributed by each customer revenue decile. Tests
--            the "80/20 rule" applicability and informs retention focus.
-- Reading:   If the top 20% generates 80%+ of revenue, prioritising
--            high-value segments for retention is well-justified. Lower
--            concentration suggests a different strategic emphasis.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW `kupferkanne-2026.sales.eda_pareto_concentration` AS
WITH customer_revenue AS (
    SELECT
        CustomerID,
        SUM(OrderValue) AS total_spend
    FROM `kupferkanne-2026.sales.stg_orders_validated`
    GROUP BY CustomerID
),

ranked AS (
    SELECT
        CustomerID,
        total_spend,
        NTILE(10) OVER (ORDER BY total_spend DESC) AS revenue_decile
    FROM customer_revenue
),

grand_total AS (
    SELECT SUM(total_spend) AS total_spend
    FROM customer_revenue
)

SELECT
    r.revenue_decile,
    COUNT(*) AS customers_in_decile,
    ROUND(SUM(r.total_spend), 2) AS decile_revenue,
    ROUND(SUM(r.total_spend) * 100.0 / g.total_spend, 2) AS pct_of_total_revenue
FROM ranked AS r
CROSS JOIN grand_total AS g
GROUP BY r.revenue_decile, g.total_spend
ORDER BY r.revenue_decile;

-- -----------------------------------------------------------------------------
-- 8. eda_basket_composition
-- -----------------------------------------------------------------------------
-- Purpose:   Average items per order by country. Cross-validates that the
--            line-grain join (items table) aligns with order-grain
--            expectations.
-- Reading:   Sudden divergence between countries can flag data quality
--            issues. Provides a baseline for an items-per-order Power BI
--            measure.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW `kupferkanne-2026.sales.eda_basket_composition` AS
SELECT
    o.Country,
    COUNT(DISTINCT o.OrderID) AS order_count,
    COUNT(i.OrderID) AS line_count,
    ROUND(
        COUNT(i.OrderID) * 1.0 / NULLIF(COUNT(DISTINCT o.OrderID), 0),
        2
    ) AS avg_items_per_order
FROM `kupferkanne-2026.sales.stg_orders_validated` AS o
LEFT JOIN `kupferkanne-2026.sales.stg_items_validated` AS i
    ON o.OrderID = i.OrderID
GROUP BY o.Country
ORDER BY avg_items_per_order DESC;
