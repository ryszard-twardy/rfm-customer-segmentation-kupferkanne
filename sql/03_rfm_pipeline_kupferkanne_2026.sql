-- ============================================================================
-- STEP 03: RFM CUSTOMER SEGMENTATION PIPELINE
-- ============================================================================
-- Prerequisites:
--   1. Run Step 00.0 and 00.1 so audit and standardised lookup views exist.
--   2. Run Step 01.0 and 01.1 so validated staging tables are ready.
--   3. Run Step 02 (eda_*) so exploratory views inform design choices below.
--
-- Purpose:
--   Join the validated fact layer with standardised lookups, build an
--   order-level curated mart, derive a deterministic customer-level RFM
--   snapshot, and expose BI-friendly semantic views.
--
-- Design rationale (informed by Step 02 EDA layer):
--   * Recency anchor = MAX(order_date), not CURRENT_DATE
--     (see eda_recency_distribution; dataset boundary is fixed).
--   * NTILE(5) quintiles for R/F/M scores
--     (see eda_order_value_distribution + eda_customer_frequency_distribution).
--   * Six-segment thresholds calibrated to composite score distribution
--     (see eda_pareto_concentration for 80/20 spend skew).
-- ============================================================================

DECLARE tz STRING DEFAULT 'Europe/Berlin';
DECLARE run_date DATE DEFAULT CURRENT_DATE(tz);

-- STEP 1: ORDER-LEVEL CURATED FACT --------------------------------------------
DROP TABLE IF EXISTS `kupferkanne-2026.sales.sales_curated`;
CREATE OR REPLACE TABLE `kupferkanne-2026.sales.sales_curated`
CLUSTER BY customer_id, order_id AS
SELECT
    o.order_id,
    o.customer_id,
    o.order_date,
    c.country,
    c.state,
    c.city,
    o.order_discount_pct,
    o.basket_item_count,
    ROUND(SUM(i.line_net_amount), 2) AS order_value,
    ROUND(SUM(i.quantity * p.unit_cost), 2) AS order_cost,
    ROUND(SUM(i.line_net_amount) - SUM(i.quantity * p.unit_cost), 2) AS order_profit,
    ROUND(
        SAFE_DIVIDE(SUM(i.line_net_amount) - SUM(i.quantity * p.unit_cost), SUM(i.line_net_amount)),
        4
    ) AS order_margin_pct,
    SUM(i.quantity) AS total_units,
    COUNT(DISTINCT i.product_id) AS distinct_products,
    ARRAY_AGG(p.product_category ORDER BY i.line_net_amount DESC, i.product_id ASC LIMIT 1
    )[OFFSET(0)] AS dominant_category,
    ARRAY_AGG(p.brand ORDER BY i.line_net_amount DESC, i.product_id ASC LIMIT 1
    )[OFFSET(0)] AS dominant_brand,
    o.source_month
FROM `kupferkanne-2026.sales.stg_orders_validated` AS o
INNER JOIN `kupferkanne-2026.sales.stg_items_validated` AS i
    ON o.order_id = i.order_id
INNER JOIN `kupferkanne-2026.sales.v_dim_products_std` AS p
    ON i.product_id = p.product_id
LEFT JOIN `kupferkanne-2026.sales.v_dim_customers_std` AS c
    ON o.customer_id = c.customer_id
GROUP BY
    o.order_id,
    o.customer_id,
    o.order_date,
    c.country,
    c.state,
    c.city,
    o.order_discount_pct,
    o.basket_item_count,
    o.source_month;

-- STEP 2: CUSTOMER-LEVEL RFM SNAPSHOT -----------------------------------------
DROP TABLE IF EXISTS `kupferkanne-2026.sales.rfm_customer_segments`;
CREATE OR REPLACE TABLE `kupferkanne-2026.sales.rfm_customer_segments`
CLUSTER BY rfm_segment, customer_id AS
WITH data_cutoff AS (
    SELECT MAX(order_date) AS data_as_of_date
    FROM `kupferkanne-2026.sales.sales_curated`
),

customer_rfm AS (
    SELECT
        customer_id,
        MAX(order_date) AS last_order_date,
        DATE_DIFF((SELECT data_as_of_date FROM data_cutoff), MAX(order_date), DAY) AS recency_days,
        COUNT(DISTINCT order_id) AS frequency_orders,
        ROUND(SUM(order_value), 2) AS monetary_value,
        ROUND(SUM(order_profit), 2) AS total_profit,
        ROUND(SAFE_DIVIDE(SUM(order_profit), SUM(order_value)), 4) AS avg_margin_pct,
        ROUND(AVG(order_value), 2) AS avg_order_value,
        SUM(total_units) AS total_units,
        ROUND(AVG(distinct_products), 1) AS avg_products_per_order,
        ARRAY_AGG(
            STRUCT(country, state, city, order_date, order_id)
            ORDER BY order_date DESC, order_id DESC LIMIT 1
        )[OFFSET(0)
        ] AS latest_geo
    FROM `kupferkanne-2026.sales.sales_curated`
    GROUP BY customer_id
),

scored AS (
    SELECT
        *,
        NTILE(5) OVER (ORDER BY recency_days DESC, customer_id ASC) AS r_score,
        NTILE(5) OVER (ORDER BY frequency_orders ASC, customer_id ASC) AS f_score,
        NTILE(5) OVER (ORDER BY monetary_value ASC, customer_id ASC) AS m_score
    FROM customer_rfm
)

SELECT
    customer_id,
    run_date AS snapshot_date,
    (SELECT data_as_of_date FROM data_cutoff) AS data_as_of_date,
    last_order_date,
    recency_days,
    frequency_orders,
    monetary_value,
    total_profit,
    avg_margin_pct,
    avg_order_value,
    total_units,
    avg_products_per_order,
    latest_geo.country AS primary_country,
    latest_geo.state AS primary_state,
    latest_geo.city AS primary_city,
    r_score,
    f_score,
    m_score,
    FORMAT('R%02dF%02dM%02d', r_score, f_score, m_score) AS rfm_cell,
    (r_score + f_score + m_score) AS rfm_total_score,
    CASE
        WHEN (r_score + f_score + m_score) >= 13 THEN 'Champions'
        WHEN (r_score + f_score + m_score) >= 11 THEN 'Loyal Customers'
        WHEN (r_score + f_score + m_score) >= 9 THEN 'Potential Loyalists'
        WHEN (r_score + f_score + m_score) >= 7 THEN 'Recent Customers'
        WHEN (r_score + f_score + m_score) >= 5 THEN 'At Risk'
        ELSE 'Hibernating'
    END AS rfm_segment,
    CASE
        WHEN (r_score + f_score + m_score) >= 13 THEN 'Reward and cross-sell premium'
        WHEN (r_score + f_score + m_score) >= 11 THEN 'Loyalty programme and early access'
        WHEN (r_score + f_score + m_score) >= 9 THEN 'Upsell and increase frequency'
        WHEN (r_score + f_score + m_score) >= 7 THEN 'Onboarding and second purchase push'
        WHEN (r_score + f_score + m_score) >= 5 THEN 'Win-back campaign and incentives'
        ELSE 'Deep discount or sunset'
    END AS recommended_action
FROM scored;

-- STEP 3: SEMANTIC VIEWS -------------------------------------------------------
CREATE OR REPLACE VIEW `kupferkanne-2026.sales.v_rfm_for_bi` AS
SELECT
    customer_id,
    data_as_of_date AS analysis_date,
    last_order_date,
    recency_days,
    frequency_orders AS order_count,
    monetary_value AS total_spend,
    total_profit,
    avg_margin_pct AS margin_pct,
    avg_order_value,
    total_units,
    avg_products_per_order,
    primary_country AS country,
    primary_state AS state,
    primary_city AS city,
    r_score,
    f_score,
    m_score,
    rfm_cell,
    rfm_total_score AS health_score,
    rfm_segment AS segment,
    recommended_action AS action
FROM `kupferkanne-2026.sales.rfm_customer_segments`;

CREATE OR REPLACE VIEW `kupferkanne-2026.sales.v_product_analytics` AS
SELECT
    sc.order_id,
    sc.customer_id,
    sc.order_date,
    sc.country,
    sc.state,
    sc.city,
    sc.order_discount_pct,
    sc.order_value,
    sc.order_cost,
    sc.order_profit,
    sc.order_margin_pct,
    i.product_id,
    p.product_name,
    p.product_category,
    p.brand,
    p.margin_pct AS product_margin_pct,
    i.quantity AS `quantity`,
    i.unit_price,
    i.line_net_amount AS line_revenue,
    ROUND(i.quantity * p.unit_cost, 2) AS line_cost,
    ROUND(i.line_net_amount - (i.quantity * p.unit_cost), 2) AS line_profit
FROM `kupferkanne-2026.sales.sales_curated` AS sc
INNER JOIN `kupferkanne-2026.sales.stg_items_validated` AS i
    ON sc.order_id = i.order_id
INNER JOIN `kupferkanne-2026.sales.v_dim_products_std` AS p
    ON i.product_id = p.product_id;

-- STEP 4: VALIDATION -----------------------------------------------------------
SELECT
    rfm_segment,
    recommended_action,
    COUNT(*) AS customer_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_total,
    ROUND(AVG(monetary_value), 2) AS avg_monetary,
    ROUND(AVG(total_profit), 2) AS avg_profit,
    ROUND(AVG(avg_margin_pct) * 100, 1) AS avg_margin_pct,
    ROUND(AVG(recency_days), 0) AS avg_recency_days,
    ROUND(AVG(frequency_orders), 1) AS avg_frequency,
    MIN(rfm_total_score) AS min_score,
    MAX(rfm_total_score) AS max_score
FROM `kupferkanne-2026.sales.rfm_customer_segments`
GROUP BY rfm_segment, recommended_action
ORDER BY MIN(rfm_total_score) DESC;
