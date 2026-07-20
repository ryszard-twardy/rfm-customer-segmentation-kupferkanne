-- FILENAME: 04_items_for_bi_kupferkanne_2026.sql
-- ============================================================================
-- STEP 04: LINE-GRAIN FACT FOR POWER BI
-- ============================================================================
-- Purpose:
--   Expose line-grain fact denormalized with order_date + customer_id so Power BI
--   can relate directly to dim_products, dim_Date, dim_customers without
--   bidirectional cross-filter via sales_curated.
--
-- Grain: one row per order line (~275K rows)
-- ============================================================================

CREATE OR REPLACE VIEW `kupferkanne-2026.sales.v_items_for_bi`
OPTIONS (description = 'BI-facing order-line fact carrying quantity, line net amount, line profit, and margin, keyed to customer, product, and order date.')  -- noqa: LT05
AS
SELECT
    i.order_id,
    i.product_id,
    sc.customer_id,
    sc.order_date,
    i.quantity AS `quantity`,
    ROUND(i.line_net_amount, 2) AS line_net_amount,
    ROUND(i.line_net_amount - (i.quantity * p.unit_cost), 2) AS line_profit,
    ROUND(SAFE_DIVIDE(
        i.line_net_amount - (i.quantity * p.unit_cost),
        i.line_net_amount
    ), 4) AS line_margin_pct
FROM `kupferkanne-2026.sales.stg_items_validated` AS i
INNER JOIN `kupferkanne-2026.sales.sales_curated` AS sc
    ON i.order_id = sc.order_id
INNER JOIN `kupferkanne-2026.sales.v_dim_products_std` AS p
    ON i.product_id = p.product_id;

-- Validation: row count ~275K, SUM(line_net_amount) ≈ €8.53M (header parity)
SELECT
    COUNT(*) AS line_rows,
    ROUND(SUM(line_net_amount), 2) AS total_revenue,
    ROUND(SUM(line_profit), 2) AS total_profit
FROM `kupferkanne-2026.sales.v_items_for_bi`;
