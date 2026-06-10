-- ============================================================================
-- STEP 01.1: POST-CLEAN VALIDATION
-- ============================================================================
-- Purpose:
--   Validate the cleaned staging layer after Step 01. This is a different
--   control from the raw audit in Step 00.
--
-- Prerequisites:
--   Run Step 00.1 so the standardised lookup views exist.
--
-- Output:
--   kupferkanne-2026.sales.data_quality_audit_cleaned
-- ============================================================================

CREATE OR REPLACE TABLE `kupferkanne-2026.sales.data_quality_audit_cleaned` AS
WITH
orders_clean AS (
    SELECT *
    FROM `kupferkanne-2026.sales.stg_orders_validated`
),

items_clean AS (
    SELECT *
    FROM `kupferkanne-2026.sales.stg_items_validated`
),

dim_c AS (
    SELECT DISTINCT customer_id AS id
    FROM `kupferkanne-2026.sales.v_dim_customers_std`
    WHERE customer_id IS NOT NULL
),

dim_p AS (
    SELECT DISTINCT product_id AS id
    FROM `kupferkanne-2026.sales.v_dim_products_std`
    WHERE product_id IS NOT NULL
),

item_order_counts AS (
    SELECT
        order_id,
        COUNT(*) AS actual_distinct_lines
    FROM `kupferkanne-2026.sales.stg_items_validated`
    GROUP BY order_id
),

ob AS (SELECT COUNT(*) AS n FROM orders_clean),

ib AS (SELECT COUNT(*) AS n FROM items_clean),

c01 AS (
    SELECT
        1 AS seq,
        'NULL order_id' AS chk,
        'stg_orders_validated.order_id' AS col,
        COUNTIF(order_id IS NULL) AS cnt,
        (SELECT n FROM ob) AS tot,
        'CRITICAL' AS sev,
        'Should be zero after cleaning' AS fix
    FROM orders_clean
),

c02 AS (
    SELECT
        2,
        'NULL customer_id',
        'stg_orders_validated.customer_id',
        COUNTIF(customer_id IS NULL),
        (SELECT n FROM ob),
        'CRITICAL',
        'Should be zero after cleaning'
    FROM orders_clean
),

c03 AS (
    SELECT
        3,
        'Orphan customer_id',
        'stg_orders_validated.customer_id',
        COUNTIF(customer_id IS NOT NULL AND customer_id NOT IN (SELECT id FROM dim_c)),
        (SELECT n FROM ob),
        'HIGH',
        'Should be zero after cleaning and dimension standardisation'
    FROM orders_clean
),

c04 AS (
    SELECT
        4,
        'NULL order_date',
        'stg_orders_validated.order_date',
        COUNTIF(order_date IS NULL),
        (SELECT n FROM ob),
        'CRITICAL',
        'Should be zero after cleaning'
    FROM orders_clean
),

c05 AS (
    SELECT
        5,
        'Future order_date',
        'stg_orders_validated.order_date',
        COUNTIF(order_date > CURRENT_DATE()),
        (SELECT n FROM ob),
        'HIGH',
        'Should be zero after cleaning'
    FROM orders_clean
),

c06 AS (
    SELECT
        6,
        'Duplicate order_id',
        'stg_orders_validated.order_id',
        COUNT(*) - COUNT(DISTINCT order_id),
        (SELECT n FROM ob),
        'HIGH',
        'Should be zero after order de-duplication'
    FROM orders_clean
),

c07 AS (
    SELECT
        7,
        'Orders with no validated items',
        'stg_orders_validated -> stg_items_validated',
        COUNTIF(order_id NOT IN (SELECT DISTINCT order_id FROM items_clean)),
        (SELECT n FROM ob),
        'HIGH',
        'Orders dropped from sales_curated by INNER JOIN to validated items in Step 02'
    FROM orders_clean
),

c08 AS (
    SELECT
        8,
        'Basket count mismatch vs validated items',
        'stg_orders_validated.basket_item_count',
        COUNTIF(basket_item_count IS NOT NULL AND basket_item_count != actual_distinct_lines),
        COUNT(*),
        'MEDIUM',
        'Review whether basket_item_count should represent distinct products or raw line count'
    FROM orders_clean
    LEFT JOIN item_order_counts ON orders_clean.order_id = item_order_counts.order_id
),

c09 AS (
    SELECT
        9,
        'Discount pct out of range',
        'stg_orders_validated.order_discount_pct',
        COUNTIF(
            order_discount_pct IS NOT NULL AND (order_discount_pct < 0 OR order_discount_pct > 100)
        ),
        (SELECT n FROM ob),
        'MEDIUM',
        'Should be zero after cleaning'
    FROM orders_clean
),

c10 AS (
    SELECT
        10,
        'NULL order_id',
        'stg_items_validated.order_id',
        COUNTIF(order_id IS NULL),
        (SELECT n FROM ib),
        'CRITICAL',
        'Should be zero after cleaning'
    FROM items_clean
),

c11 AS (
    SELECT
        11,
        'NULL product_id',
        'stg_items_validated.product_id',
        COUNTIF(product_id IS NULL),
        (SELECT n FROM ib),
        'CRITICAL',
        'Should be zero after cleaning'
    FROM items_clean
),

c12 AS (
    SELECT
        12,
        'Orphan product_id',
        'stg_items_validated.product_id',
        COUNTIF(product_id IS NOT NULL AND product_id NOT IN (SELECT id FROM dim_p)),
        (SELECT n FROM ib),
        'HIGH',
        'Should be zero after cleaning and dimension standardisation'
    FROM items_clean
),

c13 AS (
    SELECT
        13,
        'Items without validated order',
        'stg_items_validated -> stg_orders_validated',
        COUNTIF(order_id NOT IN (SELECT DISTINCT order_id FROM orders_clean)),
        (SELECT n FROM ib),
        'HIGH',
        'These rows will not join into sales_curated'
    FROM items_clean
),

c14 AS (
    SELECT
        14,
        'NULL quantity',
        'stg_items_validated.quantity',
        COUNTIF(quantity IS NULL),
        (SELECT n FROM ib),
        'CRITICAL',
        'Should be zero after cleaning'
    FROM items_clean
),

c15 AS (
    SELECT
        15,
        'Non-positive quantity',
        'stg_items_validated.quantity',
        COUNTIF(quantity <= 0),
        (SELECT n FROM ib),
        'HIGH',
        'Should be zero after cleaning'
    FROM items_clean
),

c16 AS (
    SELECT
        16,
        'NULL unit_price',
        'stg_items_validated.unit_price',
        COUNTIF(unit_price IS NULL),
        (SELECT n FROM ib),
        'CRITICAL',
        'Should be zero after cleaning'
    FROM items_clean
),

c17 AS (
    SELECT
        17,
        'Non-positive unit_price',
        'stg_items_validated.unit_price',
        COUNTIF(unit_price <= 0),
        (SELECT n FROM ib),
        'HIGH',
        'Should be zero after cleaning'
    FROM items_clean
),

c18 AS (
    SELECT
        18,
        'NULL line_net_amount',
        'stg_items_validated.line_net_amount',
        COUNTIF(line_net_amount IS NULL),
        (SELECT n FROM ib),
        'CRITICAL',
        'Should be zero after cleaning'
    FROM items_clean
),

c19 AS (
    SELECT
        19,
        'Non-positive line_net_amount',
        'stg_items_validated.line_net_amount',
        COUNTIF(line_net_amount <= 0),
        (SELECT n FROM ib),
        'HIGH',
        'Should be zero after cleaning'
    FROM items_clean
),

c20 AS (
    SELECT
        20,
        'Duplicate line items',
        'stg_items_validated.order_id + product_id',
        COUNT(*) - COUNT(DISTINCT CONCAT(order_id, '|', product_id)),
        (SELECT n FROM ib),
        'HIGH',
        'Should be zero after item de-duplication'
    FROM items_clean
),

c21 AS (
    SELECT
        21,
        'NULL customer standard key',
        'v_dim_customers_std.customer_id',
        COUNTIF(customer_id IS NULL),
        COUNT(*),
        'HIGH',
        'Standardised customer keys should be present'
    FROM `kupferkanne-2026.sales.v_dim_customers_std`
),

c22 AS (
    SELECT
        22,
        'Duplicate customer standard key',
        'v_dim_customers_std.customer_id',
        COUNT(*) - COUNT(DISTINCT customer_id),
        COUNT(*),
        'HIGH',
        'Standardised customer keys should be unique'
    FROM `kupferkanne-2026.sales.v_dim_customers_std`
    WHERE customer_id IS NOT NULL
),

c23 AS (
    SELECT
        23,
        'NULL product standard key',
        'v_dim_products_std.product_id',
        COUNTIF(product_id IS NULL),
        COUNT(*),
        'HIGH',
        'Standardised product keys should be present'
    FROM `kupferkanne-2026.sales.v_dim_products_std`
),

c24 AS (
    SELECT
        24,
        'Duplicate product standard key',
        'v_dim_products_std.product_id',
        COUNT(*) - COUNT(DISTINCT product_id),
        COUNT(*),
        'HIGH',
        'Standardised product keys should be unique'
    FROM `kupferkanne-2026.sales.v_dim_products_std`
    WHERE product_id IS NOT NULL
),

c25 AS (
    SELECT
        25,
        'NULL unit_cost in product lookup',
        'v_dim_products_std.unit_cost',
        COUNTIF(unit_cost IS NULL),
        COUNT(*),
        'HIGH',
        'Unit cost is required for profit calculations in Step 02'
    FROM `kupferkanne-2026.sales.v_dim_products_std`
),

c26 AS (
    SELECT
        26,
        'stg_orders_validated row count',
        'stg_orders_validated',
        COUNT(*),
        COUNT(*),
        'INFO',
        'Reference row count'
    FROM orders_clean
),

c27 AS (
    SELECT
        27,
        'stg_items_validated row count',
        'stg_items_validated',
        COUNT(*),
        COUNT(*),
        'INFO',
        'Reference row count'
    FROM items_clean
),

c28 AS (
    SELECT
        28,
        'v_dim_customers_std row count',
        'v_dim_customers_std',
        COUNT(*),
        COUNT(*),
        'INFO',
        'Reference row count'
    FROM `kupferkanne-2026.sales.v_dim_customers_std`
),

c29 AS (
    SELECT
        29,
        'v_dim_products_std row count',
        'v_dim_products_std',
        COUNT(*),
        COUNT(*),
        'INFO',
        'Reference row count'
    FROM `kupferkanne-2026.sales.v_dim_products_std`
),

audit AS (
    SELECT * FROM c01
    UNION ALL
    SELECT * FROM c02
    UNION ALL
    SELECT * FROM c03
    UNION ALL
    SELECT * FROM c04
    UNION ALL
    SELECT * FROM c05
    UNION ALL
    SELECT * FROM c06
    UNION ALL
    SELECT * FROM c07
    UNION ALL
    SELECT * FROM c08
    UNION ALL
    SELECT * FROM c09
    UNION ALL
    SELECT * FROM c10
    UNION ALL
    SELECT * FROM c11
    UNION ALL
    SELECT * FROM c12
    UNION ALL
    SELECT * FROM c13
    UNION ALL
    SELECT * FROM c14
    UNION ALL
    SELECT * FROM c15
    UNION ALL
    SELECT * FROM c16
    UNION ALL
    SELECT * FROM c17
    UNION ALL
    SELECT * FROM c18
    UNION ALL
    SELECT * FROM c19
    UNION ALL
    SELECT * FROM c20
    UNION ALL
    SELECT * FROM c21
    UNION ALL
    SELECT * FROM c22
    UNION ALL
    SELECT * FROM c23
    UNION ALL
    SELECT * FROM c24
    UNION ALL
    SELECT * FROM c25
    UNION ALL
    SELECT * FROM c26
    UNION ALL
    SELECT * FROM c27
    UNION ALL
    SELECT * FROM c28
    UNION ALL
    SELECT * FROM c29
)

SELECT
    seq AS check_order,
    chk AS check_name,
    col AS source_column,
    sev AS severity,
    cnt AS issue_count,
    tot AS table_rows,
    ROUND(IF(tot > 0, 100.0 * cnt / tot, 0), 3) AS pct_of_table,
    fix AS handling,
    CURRENT_TIMESTAMP() AS audit_run_at
FROM audit
ORDER BY seq;

SELECT
    check_order,
    severity,
    CASE
        WHEN severity = 'INFO' THEN CONCAT(check_name, ' – ', CAST(issue_count AS STRING), ' rows.')
        WHEN issue_count = 0 THEN CONCAT(check_name, ' – No issues found.')
        ELSE
            CONCAT(
                'Found ',
                CAST(issue_count AS STRING),
                ' for ',
                check_name,
                ' (',
                CAST(pct_of_table AS STRING),
                '%) – ',
                handling
            )
    END AS finding
FROM `kupferkanne-2026.sales.data_quality_audit_cleaned`
ORDER BY check_order;
