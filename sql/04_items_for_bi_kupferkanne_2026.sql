-- FILENAME: 04_items_for_bi_kupferkanne_2026.sql
-- ============================================================================
-- STEP 04: LINE-GRAIN FACT FOR POWER BI
-- ============================================================================
-- Purpose:
--   Expose line-grain fact denormalized with OrderDate + CustomerID so Power BI
--   can relate directly to dim_products, dim_Date, dim_customers without
--   bidirectional cross-filter via sales_curated.
--
-- Grain: one row per order line (~275K rows)
-- ============================================================================

CREATE OR REPLACE VIEW `kupferkanne-2026.sales.v_items_for_bi` AS
SELECT
    i.order_id AS OrderID,
    i.product_id AS ProductID,
    sc.CustomerID,
    sc.OrderDate,
    i.quantity AS `Quantity`,
    ROUND(i.line_net_amount, 2) AS LineNetAmount,
    ROUND(i.line_net_amount - (i.quantity * p.UnitCost), 2) AS LineProfit,
    ROUND(SAFE_DIVIDE(
        i.line_net_amount - (i.quantity * p.UnitCost),
        i.line_net_amount
    ), 4) AS LineMarginPct
FROM `kupferkanne-2026.sales.stg_items_validated` AS i
INNER JOIN `kupferkanne-2026.sales.sales_curated` AS sc
    ON i.order_id = sc.OrderID
INNER JOIN `kupferkanne-2026.sales.v_dim_products_std` AS p
    ON i.product_id = p.ProductID;

-- Validation: row count ~275K, SUM(LineNetAmount) ≈ €8.53M (header parity)
SELECT
    COUNT(*) AS line_rows,
    ROUND(SUM(LineNetAmount), 2) AS total_revenue,
    ROUND(SUM(LineProfit), 2) AS total_profit
FROM `kupferkanne-2026.sales.v_items_for_bi`;
