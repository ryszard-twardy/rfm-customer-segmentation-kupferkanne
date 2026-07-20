-- =============================================================================
-- 02_eda_kupferkanne_2026.sql
-- Exploratory Data Analysis layer
--
-- Purpose:   Eight foundational EDA views on cleaned staging data, designed
--            to inform RFM segmentation design decisions in step 03.
--
-- Inputs:    stg_orders_validated, stg_items_validated (from step 01_0),
--            v_dim_customers_std (from step 00_1, country attribution)
-- Outputs:   8 views in `kupferkanne-2026.sales`, prefix `eda_`
--
-- Design:    Idempotent (CREATE OR REPLACE). View definitions select only
--            columns needed for each exploratory question to keep BQ scans
--            tight. Each view answers ONE question; composition happens in
--            downstream consumers.
--
--            Order value is derived per order as ROUND(SUM(line_net_amount), 2)
--            with items INNER JOINed - the same expression sales_curated uses
--            in step 03, so EDA and curated numbers reconcile exactly. Orders
--            without item lines are excluded from value-based views (they
--            remain visible in the frequency, recency, and basket views).
--            order_discount_pct is not applied, consistent with the curated
--            layer. Country is a customer attribute (v_dim_customers_std,
--            LEFT JOIN on customer_id); NULL country stays NULL.
--            Rewritten against the post-migration snake_case staging schema
--            (issue #11).
--
-- See ADR-0003 (pipeline order: EDA before transform).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. eda_order_value_distribution
-- -----------------------------------------------------------------------------
-- Purpose:   Percentile distribution of order value to understand the spread
--            of transaction sizes. Informs Monetary dimension binning in RFM.
-- Reading:   Q10/Q25/Q50/Q75/Q90/Q99 give the shape of the distribution. A
--            large gap between P90 and P99 indicates a long tail (whales).
-- -----------------------------------------------------------------------------

CREATE OR REPLACE VIEW `kupferkanne-2026.sales.eda_order_value_distribution`
OPTIONS (description = 'Exploratory percentile distribution (P10 to P99, plus min, max, mean) of per-order value, used to size the RFM Monetary bins.')  -- noqa: LT05
AS
WITH order_values AS (
    SELECT
        o.order_id,
        ROUND(SUM(i.line_net_amount), 2) AS order_value
    FROM `kupferkanne-2026.sales.stg_orders_validated` AS o
    INNER JOIN `kupferkanne-2026.sales.stg_items_validated` AS i
        ON o.order_id = i.order_id
    GROUP BY o.order_id
)

SELECT
    APPROX_QUANTILES(order_value, 100)[OFFSET(10)] AS p10,
    APPROX_QUANTILES(order_value, 100)[OFFSET(25)] AS p25,
    APPROX_QUANTILES(order_value, 100)[OFFSET(50)] AS median,
    APPROX_QUANTILES(order_value, 100)[OFFSET(75)] AS p75,
    APPROX_QUANTILES(order_value, 100)[OFFSET(90)] AS p90,
    APPROX_QUANTILES(order_value, 100)[OFFSET(99)] AS p99,
    MIN(order_value) AS min_value,
    MAX(order_value) AS max_value,
    ROUND(AVG(order_value), 2) AS mean_value,
    COUNT(*) AS order_count
FROM order_values;

-- -----------------------------------------------------------------------------
-- 2. eda_order_value_outliers
-- -----------------------------------------------------------------------------
-- Purpose:   Flag orders above the 99th percentile threshold. These may be
--            data entry errors, B2B bulk orders, or legitimate high-value
--            transactions.
-- Reading:   Review outliers for plausibility. If artifacts, address in the
--            cleaning layer. If legitimate, ensure RFM Monetary captures them.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW `kupferkanne-2026.sales.eda_order_value_outliers`
OPTIONS (description = 'Exploratory list of orders above the 99th-percentile value threshold, showing each order value as a multiple of P99, for outlier review.')  -- noqa: LT05
AS
WITH order_values AS (
    SELECT
        o.order_id,
        o.customer_id,
        o.order_date,
        ROUND(SUM(i.line_net_amount), 2) AS order_value
    FROM `kupferkanne-2026.sales.stg_orders_validated` AS o
    INNER JOIN `kupferkanne-2026.sales.stg_items_validated` AS i
        ON o.order_id = i.order_id
    GROUP BY o.order_id, o.customer_id, o.order_date
),

p99_threshold AS (
    SELECT APPROX_QUANTILES(order_value, 100)[OFFSET(99)] AS p99
    FROM order_values
)

SELECT
    ov.order_id,
    ov.customer_id,
    ov.order_date,
    c.country,
    ov.order_value,
    p.p99 AS p99_threshold,
    ROUND(ov.order_value / p.p99, 2) AS multiple_of_p99
FROM order_values AS ov
CROSS JOIN p99_threshold AS p
LEFT JOIN `kupferkanne-2026.sales.v_dim_customers_std` AS c
    ON ov.customer_id = c.customer_id
WHERE ov.order_value > p.p99
ORDER BY ov.order_value DESC;

-- -----------------------------------------------------------------------------
-- 3. eda_country_breakdown
-- -----------------------------------------------------------------------------
-- Purpose:   Order volume and average order value per country. Reveals market
--            concentration and country-level AOV variation. Country is the
--            customer's country (v_dim_customers_std), matching sales_curated.
-- Reading:   Identifies dominant markets by volume and high-value markets by
--            AOV. Used to inform Regional dashboard page and filter design.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW `kupferkanne-2026.sales.eda_country_breakdown`
OPTIONS (description = 'Exploratory order volume, customer count, average order value, and revenue share by customer country.')  -- noqa: LT05
AS
WITH order_values AS (
    SELECT
        o.order_id,
        o.customer_id,
        ROUND(SUM(i.line_net_amount), 2) AS order_value
    FROM `kupferkanne-2026.sales.stg_orders_validated` AS o
    INNER JOIN `kupferkanne-2026.sales.stg_items_validated` AS i
        ON o.order_id = i.order_id
    GROUP BY o.order_id, o.customer_id
),

total_revenue AS (
    SELECT SUM(order_value) AS grand_total
    FROM order_values
)

SELECT
    c.country,
    COUNT(*) AS order_count,
    COUNT(DISTINCT ov.customer_id) AS customer_count,
    ROUND(AVG(ov.order_value), 2) AS avg_order_value,
    ROUND(SUM(ov.order_value), 2) AS total_revenue,
    ROUND(SUM(ov.order_value) * 100.0 / t.grand_total, 2) AS revenue_share_pct
FROM order_values AS ov
LEFT JOIN `kupferkanne-2026.sales.v_dim_customers_std` AS c
    ON ov.customer_id = c.customer_id
CROSS JOIN total_revenue AS t
GROUP BY c.country, t.grand_total
ORDER BY total_revenue DESC;

-- -----------------------------------------------------------------------------
-- 4. eda_monthly_temporal_pattern
-- -----------------------------------------------------------------------------
-- Purpose:   Monthly order volume and revenue trend. Identifies seasonality,
--            growth trajectory, and data quality gaps (missing months).
-- Reading:   Look for seasonal patterns (e.g., Q4 lift), level shifts in
--            recent months, and unexpected gaps.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW `kupferkanne-2026.sales.eda_monthly_temporal_pattern`
OPTIONS (description = 'Exploratory monthly order volume, active customers, revenue, and average order value, used to reveal seasonality and growth.')  -- noqa: LT05
AS
WITH order_values AS (
    SELECT
        o.order_id,
        o.customer_id,
        o.order_date,
        ROUND(SUM(i.line_net_amount), 2) AS order_value
    FROM `kupferkanne-2026.sales.stg_orders_validated` AS o
    INNER JOIN `kupferkanne-2026.sales.stg_items_validated` AS i
        ON o.order_id = i.order_id
    GROUP BY o.order_id, o.customer_id, o.order_date
)

SELECT
    FORMAT_DATE('%Y-%m', order_date) AS year_month,
    COUNT(*) AS order_count,
    COUNT(DISTINCT customer_id) AS active_customers,
    ROUND(SUM(order_value), 2) AS monthly_revenue,
    ROUND(AVG(order_value), 2) AS avg_order_value
FROM order_values
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
CREATE OR REPLACE VIEW `kupferkanne-2026.sales.eda_customer_frequency_distribution`
OPTIONS (description = 'Exploratory distribution of order counts per customer, used to validate spread for the RFM Frequency quintiles.')  -- noqa: LT05
AS
WITH customer_orders AS (
    SELECT
        customer_id,
        COUNT(*) AS order_count
    FROM `kupferkanne-2026.sales.stg_orders_validated`
    GROUP BY customer_id
),

total_customers AS (
    SELECT COUNT(DISTINCT customer_id) AS grand_total
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
--            dataset's MAX(order_date). Validates the recency anchor choice.
-- Reading:   Using CURRENT_DATE() instead would inflate recency uniformly
--            (the dataset ends in the past). MAX(order_date) preserves the
--            true recency distribution. See ADR-0006 for full rationale.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW `kupferkanne-2026.sales.eda_recency_distribution`
OPTIONS (description = 'Exploratory customer counts by days-since-last-order bucket, anchored on the dataset max order date, validating the recency anchor.')  -- noqa: LT05
AS
WITH anchor AS (
    SELECT MAX(order_date) AS data_as_of_date
    FROM `kupferkanne-2026.sales.stg_orders_validated`
),

customer_recency AS (
    SELECT
        o.customer_id,
        MAX(o.order_date) AS last_order_date,
        DATE_DIFF(a.data_as_of_date, MAX(o.order_date), DAY) AS days_since_last_order
    FROM `kupferkanne-2026.sales.stg_orders_validated` AS o
    CROSS JOIN anchor AS a
    GROUP BY o.customer_id, a.data_as_of_date
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
CREATE OR REPLACE VIEW `kupferkanne-2026.sales.eda_pareto_concentration`
OPTIONS (description = 'Exploratory revenue share by customer revenue decile, testing 80/20 concentration to guide retention focus.')  -- noqa: LT05
AS
WITH order_values AS (
    SELECT
        o.order_id,
        o.customer_id,
        ROUND(SUM(i.line_net_amount), 2) AS order_value
    FROM `kupferkanne-2026.sales.stg_orders_validated` AS o
    INNER JOIN `kupferkanne-2026.sales.stg_items_validated` AS i
        ON o.order_id = i.order_id
    GROUP BY o.order_id, o.customer_id
),

customer_revenue AS (
    SELECT
        customer_id,
        SUM(order_value) AS total_spend
    FROM order_values
    GROUP BY customer_id
),

ranked AS (
    SELECT
        customer_id,
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
-- Purpose:   Average items per order by country, cross-validating the
--            declared basket size (stg_orders_validated.basket_item_count)
--            against the actual item-line count from stg_items_validated.
--            Confirms the line-grain join aligns with order-grain
--            expectations.
-- Reading:   declared_actual_mismatch_pct above 0 flags orders whose item
--            lines diverge from the declared basket size - a data quality
--            signal. Sudden divergence between countries can flag data
--            quality issues. Provides a baseline for an items-per-order
--            Power BI measure. Itemless orders stay visible here (LEFT JOIN,
--            actual_line_count = 0) precisely because they are mismatches.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW `kupferkanne-2026.sales.eda_basket_composition`
OPTIONS (description = 'Exploratory average items per order by country, cross-checking declared basket size against actual item lines as a data-quality signal.')  -- noqa: LT05
AS
WITH order_baskets AS (
    SELECT
        o.order_id,
        o.customer_id,
        o.basket_item_count AS declared_item_count,
        COUNT(i.order_id) AS actual_line_count
    FROM `kupferkanne-2026.sales.stg_orders_validated` AS o
    LEFT JOIN `kupferkanne-2026.sales.stg_items_validated` AS i
        ON o.order_id = i.order_id
    GROUP BY o.order_id, o.customer_id, o.basket_item_count
)

SELECT
    c.country,
    COUNT(*) AS order_count,
    SUM(ob.actual_line_count) AS line_count,
    ROUND(
        SUM(ob.actual_line_count) * 1.0 / NULLIF(COUNT(*), 0),
        2
    ) AS avg_items_per_order,
    ROUND(AVG(ob.declared_item_count), 2) AS avg_declared_items_per_order,
    COUNTIF(ob.actual_line_count != ob.declared_item_count)
        AS declared_actual_mismatch_count,
    ROUND(
        COUNTIF(ob.actual_line_count != ob.declared_item_count) * 100.0
        / NULLIF(COUNT(*), 0),
        2
    ) AS declared_actual_mismatch_pct
FROM order_baskets AS ob
LEFT JOIN `kupferkanne-2026.sales.v_dim_customers_std` AS c
    ON ob.customer_id = c.customer_id
GROUP BY c.country
ORDER BY avg_items_per_order DESC;
