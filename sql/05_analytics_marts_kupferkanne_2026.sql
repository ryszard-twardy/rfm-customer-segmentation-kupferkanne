-- ============================================================================
-- STEP 05: SALES ANALYTICS VIEWS
-- ============================================================================
-- Purpose:
--   Pre-aggregate curated sales data for Power BI pages focused on product,
--   brand, regional, and monthly trend analysis.
--
-- Prerequisites:
--   Run Step 03 first.
--
-- Output: 6 views
--   v_monthly_revenue         → Page 1 (monthly trend line)
--   v_product_performance     → Page 3 (top products, ranks)
--   v_brand_profitability     → Page 3 (brand margin comparison)
--   v_regional_performance    → Page 6 (country/state/city map)
--   v_category_monthly_trend  → Page 3 (category × brand × month)
--   v_country_summary         → Page 6 (country-level bars)
--
-- ============================================================================
-- CHANGELOG
-- ============================================================================
-- v2 (2026-04-22) – Author: Ryszard Twardy
--   * Patched v_monthly_revenue and v_category_monthly_trend to exclude
--     incomplete (current) month from aggregation.
--   * Problem: when dataset ends mid-month (e.g. 2026-03-15), trend lines
--     showed an artificial drop-off for the partial month, creating
--     misleading "revenue collapse" visualization.
--   * Fix: both monthly views use a shared CTE pattern that anchors on
--     MAX(order_date) from sales_curated (not CURRENT_DATE, consistent with
--     RFM pipeline anchor policy) and filters to complete months only.
--   * Logic: if MAX(order_date) is month-end, include that month; otherwise,
--     last complete month is the month BEFORE the month containing
--     MAX(order_date).
--   * Pattern is idempotent – future runs automatically adapt as new data
--     arrives. No maintenance required when months complete naturally.
--   * Other 4 views unchanged.
-- ============================================================================

-- ============================================================================
-- VIEW 1: Monthly Revenue Summary
-- ============================================================================
-- Grain: one row per complete month
-- Used by: Page 1 (revenue trend line), Page 3 (overlay on category trends)
-- Note: Incomplete (current) month is excluded – see CHANGELOG v2.
-- ============================================================================

CREATE OR REPLACE VIEW `kupferkanne-2026.sales.v_monthly_revenue`
OPTIONS (description = 'Monthly revenue, profit, margin, orders, and active customers over complete months only; the trailing partial month is excluded using the dataset max order date, not the calendar date.')  -- noqa: LT05
AS
WITH data_boundary AS (
    -- Anchor: last order_date in dataset (not CURRENT_DATE)
    -- Same principle as RFM recency anchor – ensures reproducible output
    SELECT MAX(order_date) AS last_order_date
    FROM `kupferkanne-2026.sales.sales_curated`
),

last_complete_month AS (
    -- If MAX is month-end → month is complete, include it
    -- If MAX is mid-month → month is partial, exclude (use prior month as cutoff)
    SELECT
        CASE
            WHEN last_order_date = LAST_DAY(last_order_date, MONTH)
                THEN DATE_TRUNC(last_order_date, MONTH)
            ELSE DATE_SUB(DATE_TRUNC(last_order_date, MONTH), INTERVAL 1 MONTH)
        END AS cutoff_month
    FROM data_boundary
)

SELECT
    DATE_TRUNC(sc.order_date, MONTH) AS order_month,
    FORMAT_DATE('%Y-%m', sc.order_date) AS month_label,
    EXTRACT(YEAR FROM sc.order_date) AS order_year,
    EXTRACT(MONTH FROM sc.order_date) AS order_month_num,
    COUNT(DISTINCT sc.order_id) AS total_orders,
    COUNT(DISTINCT sc.customer_id) AS active_customers,
    ROUND(SUM(sc.order_value), 2) AS total_revenue,
    ROUND(SUM(sc.order_profit), 2) AS total_profit,
    ROUND(SAFE_DIVIDE(SUM(sc.order_profit), SUM(sc.order_value)), 4) AS margin_pct,
    ROUND(AVG(sc.order_value), 2) AS avg_order_value,
    SUM(sc.total_units) AS total_units
FROM `kupferkanne-2026.sales.sales_curated` AS sc
CROSS JOIN last_complete_month AS lcm
WHERE DATE_TRUNC(sc.order_date, MONTH) <= lcm.cutoff_month
GROUP BY 1, 2, 3, 4;

-- ============================================================================
-- VIEW 2: Product Performance (unchanged)
-- ============================================================================

CREATE OR REPLACE VIEW `kupferkanne-2026.sales.v_product_performance`
OPTIONS (description = 'One row per product: revenue, units, cost, profit, and margin with overall and within-category revenue and units ranks, to surface top and bottom performers.')  -- noqa: LT05
AS
SELECT
    p.product_id,
    p.product_name,
    p.product_category,
    p.brand,
    p.retail_price,
    p.unit_cost,
    p.margin_pct AS product_margin_pct,
    COUNT(DISTINCT i.order_id) AS orders_containing,
    SUM(i.quantity) AS units_sold,
    ROUND(SUM(i.line_net_amount), 2) AS total_revenue,
    ROUND(SUM(i.quantity * p.unit_cost), 2) AS total_cost,
    ROUND(SUM(i.line_net_amount) - SUM(i.quantity * p.unit_cost), 2) AS total_profit,
    ROUND(
        SAFE_DIVIDE(SUM(i.line_net_amount) - SUM(i.quantity * p.unit_cost), SUM(i.line_net_amount)),
        4
    ) AS realized_margin_pct,
    ROUND(AVG(i.line_net_amount), 2) AS avg_line_revenue,
    ROUND(SAFE_DIVIDE(SUM(i.line_net_amount), SUM(i.quantity)), 2) AS revenue_per_unit,
    RANK() OVER (ORDER BY SUM(i.line_net_amount) DESC) AS revenue_rank,
    RANK() OVER (ORDER BY SUM(i.quantity) DESC) AS units_rank,
    RANK()
        OVER (PARTITION BY p.product_category ORDER BY SUM(i.line_net_amount) DESC)
        AS rank_within_category
FROM `kupferkanne-2026.sales.stg_items_validated` AS i
INNER JOIN `kupferkanne-2026.sales.v_dim_products_std` AS p
    ON i.product_id = p.product_id
GROUP BY
    p.product_id,
    p.product_name,
    p.product_category,
    p.brand,
    p.retail_price,
    p.unit_cost,
    p.margin_pct;

-- ============================================================================
-- VIEW 3: brand Profitability (unchanged)
-- ============================================================================

CREATE OR REPLACE VIEW `kupferkanne-2026.sales.v_brand_profitability`
OPTIONS (description = 'One row per brand: aggregated units, revenue, cost, profit, margin, and revenue share, to compare brand profitability and contribution to the range.')  -- noqa: LT05
AS
SELECT
    p.brand,
    COUNT(DISTINCT p.product_id) AS product_count,
    COUNT(DISTINCT i.order_id) AS orders_containing,
    SUM(i.quantity) AS units_sold,
    ROUND(SUM(i.line_net_amount), 2) AS total_revenue,
    ROUND(SUM(i.quantity * p.unit_cost), 2) AS total_cost,
    ROUND(SUM(i.line_net_amount) - SUM(i.quantity * p.unit_cost), 2) AS total_profit,
    ROUND(
        SAFE_DIVIDE(SUM(i.line_net_amount) - SUM(i.quantity * p.unit_cost), SUM(i.line_net_amount)),
        4
    ) AS brand_margin_pct,
    ROUND(SAFE_DIVIDE(SUM(i.line_net_amount), SUM(i.quantity)), 2) AS revenue_per_unit,
    ROUND(SAFE_DIVIDE(SUM(i.line_net_amount), SUM(SUM(i.line_net_amount)) OVER ()), 4)
        AS revenue_share
FROM `kupferkanne-2026.sales.stg_items_validated` AS i
INNER JOIN `kupferkanne-2026.sales.v_dim_products_std` AS p
    ON i.product_id = p.product_id
GROUP BY p.brand;

-- ============================================================================
-- VIEW 4: Regional Performance (unchanged)
-- ============================================================================

CREATE OR REPLACE VIEW `kupferkanne-2026.sales.v_regional_performance`
OPTIONS (description = 'One row per country-state-city: revenue, profit, margin, revenue per customer, and revenue share, to rank geographies and feed the regional map and drill-down.')  -- noqa: LT05
AS
SELECT
    country,
    state,
    city,
    COUNT(DISTINCT customer_id) AS customer_count,
    COUNT(DISTINCT order_id) AS order_count,
    ROUND(SUM(order_value), 2) AS total_revenue,
    ROUND(SUM(order_profit), 2) AS total_profit,
    ROUND(SAFE_DIVIDE(SUM(order_profit), SUM(order_value)), 4) AS margin_pct,
    ROUND(SAFE_DIVIDE(SUM(order_value), COUNT(DISTINCT customer_id)), 2) AS arpu,
    ROUND(AVG(order_value), 2) AS avg_order_value,
    ROUND(SAFE_DIVIDE(SUM(order_value), SUM(SUM(order_value)) OVER ()), 4) AS revenue_share
FROM `kupferkanne-2026.sales.sales_curated`
WHERE country IS NOT NULL
GROUP BY country, state, city;

-- ============================================================================
-- VIEW 5: Category Monthly Trend
-- ============================================================================
-- Grain: one row per category × brand × complete month
-- Used by: Page 3 (stacked area / line chart)
-- Note: Incomplete (current) month is excluded – see CHANGELOG v2.
-- Uses same anchor logic as v_monthly_revenue for consistency.
-- ============================================================================

CREATE OR REPLACE VIEW `kupferkanne-2026.sales.v_category_monthly_trend`
OPTIONS (description = 'Monthly revenue, units, profit, and margin by product category and brand over complete months only; the trailing partial month is excluded using the dataset max order date.')  -- noqa: LT05
AS
WITH data_boundary AS (
    SELECT MAX(order_date) AS last_order_date
    FROM `kupferkanne-2026.sales.sales_curated`
),

last_complete_month AS (
    SELECT
        CASE
            WHEN last_order_date = LAST_DAY(last_order_date, MONTH)
                THEN DATE_TRUNC(last_order_date, MONTH)
            ELSE DATE_SUB(DATE_TRUNC(last_order_date, MONTH), INTERVAL 1 MONTH)
        END AS cutoff_month
    FROM data_boundary
)

SELECT
    p.product_category,
    p.brand,
    DATE_TRUNC(sc.order_date, MONTH) AS order_month,
    FORMAT_DATE('%Y-%m', sc.order_date) AS month_label,
    COUNT(DISTINCT sc.order_id) AS order_count,
    SUM(i.quantity) AS units_sold,
    ROUND(SUM(i.line_net_amount), 2) AS category_revenue,
    ROUND(SUM(i.line_net_amount) - SUM(i.quantity * p.unit_cost), 2) AS category_profit,
    ROUND(SAFE_DIVIDE(
        SUM(i.line_net_amount) - SUM(i.quantity * p.unit_cost),
        SUM(i.line_net_amount)
    ), 4) AS category_margin_pct
FROM `kupferkanne-2026.sales.sales_curated` AS sc
INNER JOIN `kupferkanne-2026.sales.stg_items_validated` AS i
    ON sc.order_id = i.order_id
INNER JOIN `kupferkanne-2026.sales.v_dim_products_std` AS p
    ON i.product_id = p.product_id
CROSS JOIN last_complete_month AS lcm
WHERE DATE_TRUNC(sc.order_date, MONTH) <= lcm.cutoff_month
GROUP BY 1, 2, 3, 4;

-- ============================================================================
-- VIEW 6: country Summary (unchanged)
-- ============================================================================

CREATE OR REPLACE VIEW `kupferkanne-2026.sales.v_country_summary`
OPTIONS (description = 'One row per country: customers, orders, revenue, profit, margin, revenue per customer, and revenue share, for country-level comparison and the regional bar charts.')  -- noqa: LT05
AS
SELECT
    country,
    COUNT(DISTINCT customer_id) AS customers,
    COUNT(DISTINCT order_id) AS orders,
    ROUND(SUM(order_value), 2) AS revenue,
    ROUND(SUM(order_profit), 2) AS profit,
    ROUND(SAFE_DIVIDE(SUM(order_profit), SUM(order_value)), 4) AS margin_pct,
    ROUND(SAFE_DIVIDE(SUM(order_value), COUNT(DISTINCT customer_id)), 2) AS arpu,
    ROUND(AVG(order_value), 2) AS avg_order_value,
    ROUND(SAFE_DIVIDE(SUM(order_value), SUM(SUM(order_value)) OVER ()), 4) AS revenue_share
FROM `kupferkanne-2026.sales.sales_curated`
WHERE country IS NOT NULL
GROUP BY country;

-- ============================================================================
-- VALIDATION: row counts per view + incomplete-month sanity check
-- ============================================================================

SELECT
    'v_monthly_revenue' AS view_name,
    COUNT(*) AS rows_count
FROM `kupferkanne-2026.sales.v_monthly_revenue`
UNION ALL
SELECT
    'v_product_performance',
    COUNT(*)
FROM `kupferkanne-2026.sales.v_product_performance`
UNION ALL
SELECT
    'v_brand_profitability',
    COUNT(*)
FROM `kupferkanne-2026.sales.v_brand_profitability`
UNION ALL
SELECT
    'v_regional_performance',
    COUNT(*)
FROM `kupferkanne-2026.sales.v_regional_performance`
UNION ALL
SELECT
    'v_category_monthly_trend',
    COUNT(*)
FROM `kupferkanne-2026.sales.v_category_monthly_trend`
UNION ALL
SELECT
    'v_country_summary',
    COUNT(*)
FROM `kupferkanne-2026.sales.v_country_summary`;

-- Expected after v2 patch: v_monthly_revenue should have 38 rows (was 39 before patch)
-- Expected: MAX(order_month) in v_monthly_revenue = 2026-02-01 (not 2026-03-01)

-- Sanity check – last complete month in both monthly views:
SELECT
    'v_monthly_revenue' AS view_name,
    MAX(order_month) AS last_complete_month
FROM `kupferkanne-2026.sales.v_monthly_revenue`
UNION ALL
SELECT
    'v_category_monthly_trend',
    MAX(order_month)
FROM `kupferkanne-2026.sales.v_category_monthly_trend`;
