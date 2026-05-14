-- ============================================================================
-- STEP 05: SALES ANALYTICS VIEWS
-- ============================================================================
-- Purpose:
--   Pre-aggregate curated sales data for Power BI pages focused on product,
--   brand, regional, and monthly trend analysis.
--
-- Prerequisites:
--   Run Step 02 first.
--
-- Output: 6 views
--   v_monthly_revenue         → Page 1 (monthly trend line)
--   v_product_performance     → Page 3 (top products, ranks)
--   v_brand_profitability     → Page 3 (brand margin comparison)
--   v_regional_performance    → Page 5 (country/state/city map)
--   v_category_monthly_trend  → Page 3 (category × brand × month)
--   v_country_summary         → Page 5 (country-level bars)
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
--     MAX(OrderDate) from sales_curated (not CURRENT_DATE, consistent with
--     RFM pipeline anchor policy) and filters to complete months only.
--   * Logic: if MAX(OrderDate) is month-end, include that month; otherwise,
--     last complete month is the month BEFORE the month containing
--     MAX(OrderDate).
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

CREATE OR REPLACE VIEW `kupferkanne-2026.sales.v_monthly_revenue` AS
WITH data_boundary AS (
    -- Anchor: last OrderDate in dataset (not CURRENT_DATE)
    -- Same principle as RFM recency anchor – ensures reproducible output
    SELECT MAX(OrderDate) AS last_order_date
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
    DATE_TRUNC(sc.OrderDate, MONTH) AS order_month,
    FORMAT_DATE('%Y-%m', sc.OrderDate) AS month_label,
    EXTRACT(YEAR FROM sc.OrderDate) AS order_year,
    EXTRACT(MONTH FROM sc.OrderDate) AS order_month_num,
    COUNT(DISTINCT sc.OrderID) AS total_orders,
    COUNT(DISTINCT sc.CustomerID) AS active_customers,
    ROUND(SUM(sc.OrderValue), 2) AS total_revenue,
    ROUND(SUM(sc.OrderProfit), 2) AS total_profit,
    ROUND(SAFE_DIVIDE(SUM(sc.OrderProfit), SUM(sc.OrderValue)), 4) AS margin_pct,
    ROUND(AVG(sc.OrderValue), 2) AS avg_order_value,
    SUM(sc.TotalUnits) AS total_units
FROM `kupferkanne-2026.sales.sales_curated` AS sc
CROSS JOIN last_complete_month AS lcm
WHERE DATE_TRUNC(sc.OrderDate, MONTH) <= lcm.cutoff_month
GROUP BY 1, 2, 3, 4;

-- ============================================================================
-- VIEW 2: Product Performance (unchanged)
-- ============================================================================

CREATE OR REPLACE VIEW `kupferkanne-2026.sales.v_product_performance` AS
SELECT
    p.ProductID,
    p.ProductName,
    p.ProductCategory,
    p.Brand,
    p.RetailPrice,
    p.UnitCost,
    p.MarginPct AS product_margin_pct,
    COUNT(DISTINCT i.order_id) AS orders_containing,
    SUM(i.quantity) AS units_sold,
    ROUND(SUM(i.line_net_amount), 2) AS total_revenue,
    ROUND(SUM(i.quantity * p.UnitCost), 2) AS total_cost,
    ROUND(SUM(i.line_net_amount) - SUM(i.quantity * p.UnitCost), 2) AS total_profit,
    ROUND(
        SAFE_DIVIDE(SUM(i.line_net_amount) - SUM(i.quantity * p.UnitCost), SUM(i.line_net_amount)),
        4
    ) AS realized_margin_pct,
    ROUND(AVG(i.line_net_amount), 2) AS avg_line_revenue,
    ROUND(SAFE_DIVIDE(SUM(i.line_net_amount), SUM(i.quantity)), 2) AS revenue_per_unit,
    RANK() OVER (ORDER BY SUM(i.line_net_amount) DESC) AS revenue_rank,
    RANK() OVER (ORDER BY SUM(i.quantity) DESC) AS units_rank,
    RANK()
        OVER (PARTITION BY p.ProductCategory ORDER BY SUM(i.line_net_amount) DESC)
        AS rank_within_category
FROM `kupferkanne-2026.sales.stg_items_validated` AS i
INNER JOIN `kupferkanne-2026.sales.v_dim_products_std` AS p
    ON i.product_id = p.ProductID
GROUP BY
    p.ProductID, p.ProductName, p.ProductCategory, p.Brand, p.RetailPrice, p.UnitCost, p.MarginPct;

-- ============================================================================
-- VIEW 3: Brand Profitability (unchanged)
-- ============================================================================

CREATE OR REPLACE VIEW `kupferkanne-2026.sales.v_brand_profitability` AS
SELECT
    p.Brand,
    COUNT(DISTINCT p.ProductID) AS product_count,
    COUNT(DISTINCT i.order_id) AS orders_containing,
    SUM(i.quantity) AS units_sold,
    ROUND(SUM(i.line_net_amount), 2) AS total_revenue,
    ROUND(SUM(i.quantity * p.UnitCost), 2) AS total_cost,
    ROUND(SUM(i.line_net_amount) - SUM(i.quantity * p.UnitCost), 2) AS total_profit,
    ROUND(
        SAFE_DIVIDE(SUM(i.line_net_amount) - SUM(i.quantity * p.UnitCost), SUM(i.line_net_amount)),
        4
    ) AS brand_margin_pct,
    ROUND(SAFE_DIVIDE(SUM(i.line_net_amount), SUM(i.quantity)), 2) AS revenue_per_unit,
    ROUND(SAFE_DIVIDE(SUM(i.line_net_amount), SUM(SUM(i.line_net_amount)) OVER ()), 4)
        AS revenue_share
FROM `kupferkanne-2026.sales.stg_items_validated` AS i
INNER JOIN `kupferkanne-2026.sales.v_dim_products_std` AS p
    ON i.product_id = p.ProductID
GROUP BY p.Brand;

-- ============================================================================
-- VIEW 4: Regional Performance (unchanged)
-- ============================================================================

CREATE OR REPLACE VIEW `kupferkanne-2026.sales.v_regional_performance` AS
SELECT
    Country,
    State,
    City,
    COUNT(DISTINCT CustomerID) AS customer_count,
    COUNT(DISTINCT OrderID) AS order_count,
    ROUND(SUM(OrderValue), 2) AS total_revenue,
    ROUND(SUM(OrderProfit), 2) AS total_profit,
    ROUND(SAFE_DIVIDE(SUM(OrderProfit), SUM(OrderValue)), 4) AS margin_pct,
    ROUND(SAFE_DIVIDE(SUM(OrderValue), COUNT(DISTINCT CustomerID)), 2) AS arpu,
    ROUND(AVG(OrderValue), 2) AS avg_order_value,
    ROUND(SAFE_DIVIDE(SUM(OrderValue), SUM(SUM(OrderValue)) OVER ()), 4) AS revenue_share
FROM `kupferkanne-2026.sales.sales_curated`
WHERE Country IS NOT NULL
GROUP BY Country, State, City;

-- ============================================================================
-- VIEW 5: Category Monthly Trend
-- ============================================================================
-- Grain: one row per category × brand × complete month
-- Used by: Page 3 (stacked area / line chart)
-- Note: Incomplete (current) month is excluded – see CHANGELOG v2.
-- Uses same anchor logic as v_monthly_revenue for consistency.
-- ============================================================================

CREATE OR REPLACE VIEW `kupferkanne-2026.sales.v_category_monthly_trend` AS
WITH data_boundary AS (
    SELECT MAX(OrderDate) AS last_order_date
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
    p.ProductCategory,
    p.Brand,
    DATE_TRUNC(sc.OrderDate, MONTH) AS order_month,
    FORMAT_DATE('%Y-%m', sc.OrderDate) AS month_label,
    COUNT(DISTINCT sc.OrderID) AS order_count,
    SUM(i.quantity) AS units_sold,
    ROUND(SUM(i.line_net_amount), 2) AS category_revenue,
    ROUND(SUM(i.line_net_amount) - SUM(i.quantity * p.UnitCost), 2) AS category_profit,
    ROUND(SAFE_DIVIDE(
        SUM(i.line_net_amount) - SUM(i.quantity * p.UnitCost),
        SUM(i.line_net_amount)
    ), 4) AS category_margin_pct
FROM `kupferkanne-2026.sales.sales_curated` AS sc
INNER JOIN `kupferkanne-2026.sales.stg_items_validated` AS i
    ON sc.OrderID = i.order_id
INNER JOIN `kupferkanne-2026.sales.v_dim_products_std` AS p
    ON i.product_id = p.ProductID
CROSS JOIN last_complete_month AS lcm
WHERE DATE_TRUNC(sc.OrderDate, MONTH) <= lcm.cutoff_month
GROUP BY 1, 2, 3, 4;

-- ============================================================================
-- VIEW 6: Country Summary (unchanged)
-- ============================================================================

CREATE OR REPLACE VIEW `kupferkanne-2026.sales.v_country_summary` AS
SELECT
    Country,
    COUNT(DISTINCT CustomerID) AS customers,
    COUNT(DISTINCT OrderID) AS orders,
    ROUND(SUM(OrderValue), 2) AS revenue,
    ROUND(SUM(OrderProfit), 2) AS profit,
    ROUND(SAFE_DIVIDE(SUM(OrderProfit), SUM(OrderValue)), 4) AS margin_pct,
    ROUND(SAFE_DIVIDE(SUM(OrderValue), COUNT(DISTINCT CustomerID)), 2) AS arpu,
    ROUND(AVG(OrderValue), 2) AS avg_order_value,
    ROUND(SAFE_DIVIDE(SUM(OrderValue), SUM(SUM(OrderValue)) OVER ()), 4) AS revenue_share
FROM `kupferkanne-2026.sales.sales_curated`
WHERE Country IS NOT NULL
GROUP BY Country;

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
