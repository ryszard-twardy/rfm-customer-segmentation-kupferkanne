-- ============================================================================
-- STEP 01: DATA CLEANING PIPELINE
-- ============================================================================
-- Purpose:
--   Clean both fact streams independently and produce validated staging tables.
--
-- Assumptions:
--   1. Monthly fact shards share a stable physical schema, so wildcard reads
--      are safe. Step 00 audits this contract explicitly.
--   2. Lookup-table standardisation is handled in Step 00.1.
--
-- Outputs:
--   stg_orders_intake, stg_orders_cleaned, stg_orders_validated
--   stg_items_intake,  stg_items_cleaned,  stg_items_validated
--   cleaning_log
-- ============================================================================

DECLARE start_year INT64 DEFAULT 2023;
DECLARE include_open_current_month BOOL DEFAULT FALSE;
DECLARE tz STRING DEFAULT 'Europe/Berlin';
DECLARE run_date DATE DEFAULT CURRENT_DATE(tz);
DECLARE start_suffix STRING DEFAULT FORMAT_DATE('%y%m', DATE(start_year, 1, 1));
DECLARE end_suffix STRING DEFAULT FORMAT_DATE(
    '%y%m',
    IF(
        include_open_current_month, run_date,
        DATE_SUB(DATE_TRUNC(run_date, MONTH), INTERVAL 1 MONTH)
    )
);

-- ORDERS INTAKE ----------------------------------------------------------------
CREATE OR REPLACE TABLE `kupferkanne-2026.sales.stg_orders_intake` AS
SELECT
    GENERATE_UUID() AS row_id,
    CAST(OrderID AS STRING) AS raw_order_id,
    CAST(CustomerID AS STRING) AS raw_customer_id,
    CAST(OrderDate AS STRING) AS raw_order_date,
    CAST(OrderDiscountPct AS STRING) AS raw_order_discount_pct,
    CAST(BasketItemCount AS STRING) AS raw_basket_item_count,
    NULLIF(TRIM(CAST(OrderID AS STRING)), '') AS order_id,
    NULLIF(TRIM(CAST(CustomerID AS STRING)), '') AS customer_id,
    SAFE_CAST(NULLIF(TRIM(CAST(OrderDate AS STRING)), '') AS DATE) AS order_date,
    SAFE_CAST(NULLIF(TRIM(CAST(OrderDiscountPct AS STRING)), '') AS NUMERIC)
        AS order_discount_pct_raw,
    SAFE_CAST(NULLIF(TRIM(CAST(BasketItemCount AS STRING)), '') AS INT64) AS basket_item_count_raw,
    _TABLE_SUFFIX AS source_month
FROM `kupferkanne-2026.sales.orders20*`
WHERE _TABLE_SUFFIX BETWEEN start_suffix AND end_suffix;

-- ITEMS INTAKE -----------------------------------------------------------------
CREATE OR REPLACE TABLE `kupferkanne-2026.sales.stg_items_intake` AS
SELECT
    GENERATE_UUID() AS row_id,
    CAST(OrderID AS STRING) AS raw_order_id,
    CAST(ProductID AS STRING) AS raw_product_id,
    CAST(Quantity AS STRING) AS raw_quantity,
    CAST(UnitPrice AS STRING) AS raw_unit_price,
    CAST(LineNetAmount AS STRING) AS raw_line_amount,
    NULLIF(TRIM(CAST(OrderID AS STRING)), '') AS order_id,
    NULLIF(TRIM(CAST(ProductID AS STRING)), '') AS product_id,
    SAFE_CAST(NULLIF(TRIM(CAST(Quantity AS STRING)), '') AS INT64) AS quantity_raw,
    SAFE_CAST(NULLIF(TRIM(CAST(UnitPrice AS STRING)), '') AS NUMERIC) AS unit_price_raw,
    SAFE_CAST(NULLIF(TRIM(CAST(LineNetAmount AS STRING)), '') AS NUMERIC) AS line_net_amount_raw,
    _TABLE_SUFFIX AS source_month
FROM `kupferkanne-2026.sales.items20*`
WHERE _TABLE_SUFFIX BETWEEN start_suffix AND end_suffix;

-- ORDERS CLEANING --------------------------------------------------------------
CREATE OR REPLACE TABLE `kupferkanne-2026.sales.stg_orders_cleaned` AS
SELECT
    row_id,
    source_month,
    raw_order_id,
    raw_customer_id,
    raw_order_date,
    raw_order_discount_pct,
    raw_basket_item_count,
    order_id,
    customer_id,
    CASE
        WHEN order_date IS NULL THEN NULL
        WHEN order_date > CURRENT_DATE() THEN NULL
        WHEN order_date < DATE(2020, 1, 1) THEN NULL
        ELSE order_date
    END AS order_date,
    CASE
        WHEN order_discount_pct_raw IS NULL THEN NULL
        WHEN order_discount_pct_raw < 0 OR order_discount_pct_raw > 100 THEN NULL
        ELSE order_discount_pct_raw
    END AS order_discount_pct,
    CASE
        WHEN basket_item_count_raw IS NULL THEN NULL
        WHEN basket_item_count_raw <= 0 THEN NULL
        ELSE basket_item_count_raw
    END AS basket_item_count,
    ARRAY_TO_STRING(ARRAY_CONCAT(
        IF(raw_order_id IS NOT NULL AND TRIM(raw_order_id) = '', ['BLANK_ORDER_ID'], []),
        IF(raw_customer_id IS NOT NULL AND TRIM(raw_customer_id) = '', ['BLANK_CUSTOMER_ID'], []),
        IF(raw_order_date IS NOT NULL AND TRIM(raw_order_date) = '', ['BLANK_DATE'], []),
        IF(
            raw_order_id != TRIM(raw_order_id) OR raw_customer_id != TRIM(raw_customer_id),
            ['TRIMMED_KEYS'],
            []
        ),
        IF(raw_order_id IS NULL, ['NULL_ORDER_ID'], []),
        IF(raw_customer_id IS NULL, ['NULL_CUSTOMER_ID'], []),
        IF(raw_order_date IS NULL, ['NULL_DATE'], []),
        IF(
            raw_order_date IS NOT NULL AND TRIM(raw_order_date) != '' AND order_date IS NULL,
            ['UNPARSEABLE_DATE'],
            []
        ),
        IF(order_date > CURRENT_DATE(), ['FUTURE_DATE'], []),
        IF(order_date < DATE(2020, 1, 1), ['TOO_EARLY_DATE'], []),
        IF(
            raw_order_discount_pct IS NOT NULL AND TRIM(raw_order_discount_pct) = '',
            ['BLANK_DISCOUNT_PCT'],
            []
        ),
        IF(
            raw_order_discount_pct IS NOT NULL
            AND TRIM(raw_order_discount_pct) != ''
            AND order_discount_pct_raw IS NULL,
            ['UNPARSEABLE_DISCOUNT_PCT'],
            []
        ),
        IF(
            order_discount_pct_raw < 0 OR order_discount_pct_raw > 100,
            ['DISCOUNT_PCT_OUT_OF_RANGE'],
            []
        ),
        IF(
            raw_basket_item_count IS NOT NULL AND TRIM(raw_basket_item_count) = '',
            ['BLANK_BASKET_COUNT'],
            []
        ),
        IF(
            raw_basket_item_count IS NOT NULL
            AND TRIM(raw_basket_item_count) != ''
            AND basket_item_count_raw IS NULL,
            ['UNPARSEABLE_BASKET_COUNT'],
            []
        ),
        IF(basket_item_count_raw <= 0, ['NON_POSITIVE_BASKET_COUNT'], [])
    ), '|') AS cleaning_flags
FROM `kupferkanne-2026.sales.stg_orders_intake`;

-- ITEMS CLEANING ---------------------------------------------------------------
CREATE OR REPLACE TABLE `kupferkanne-2026.sales.stg_items_cleaned` AS
SELECT
    row_id,
    source_month,
    raw_order_id,
    raw_product_id,
    raw_quantity,
    raw_unit_price,
    raw_line_amount,
    order_id,
    product_id,
    CASE
        WHEN quantity_raw IS NULL THEN NULL
        WHEN quantity_raw <= 0 THEN NULL
        ELSE quantity_raw
    END AS quantity,
    CASE
        WHEN unit_price_raw IS NULL THEN NULL
        WHEN unit_price_raw <= 0 THEN NULL
        ELSE ROUND(unit_price_raw, 2)
    END AS unit_price,
    CASE
        WHEN line_net_amount_raw IS NULL THEN NULL
        WHEN line_net_amount_raw < 0 THEN NULL
        WHEN line_net_amount_raw = 0 THEN NULL
        WHEN
            line_net_amount_raw > 1000 AND line_net_amount_raw / 100 BETWEEN 1 AND 500
            THEN ROUND(line_net_amount_raw / 100, 2)
        ELSE ROUND(line_net_amount_raw, 2)
    END AS line_net_amount,
    ARRAY_TO_STRING(ARRAY_CONCAT(
        IF(raw_order_id IS NOT NULL AND TRIM(raw_order_id) = '', ['BLANK_ORDER_ID'], []),
        IF(raw_product_id IS NOT NULL AND TRIM(raw_product_id) = '', ['BLANK_PRODUCT_ID'], []),
        IF(
            raw_order_id != TRIM(raw_order_id) OR raw_product_id != TRIM(raw_product_id),
            ['TRIMMED_KEYS'],
            []
        ),
        IF(raw_order_id IS NULL, ['NULL_ORDER_ID'], []),
        IF(raw_product_id IS NULL, ['NULL_PRODUCT_ID'], []),
        IF(raw_quantity IS NULL, ['NULL_QUANTITY'], []),
        IF(raw_quantity IS NOT NULL AND TRIM(raw_quantity) = '', ['BLANK_QUANTITY'], []),
        IF(
            raw_quantity IS NOT NULL AND TRIM(raw_quantity) != '' AND quantity_raw IS NULL,
            ['UNPARSEABLE_QUANTITY'],
            []
        ),
        IF(quantity_raw <= 0, ['NON_POSITIVE_QUANTITY'], []),
        IF(raw_unit_price IS NULL, ['NULL_UNIT_PRICE'], []),
        IF(raw_unit_price IS NOT NULL AND TRIM(raw_unit_price) = '', ['BLANK_UNIT_PRICE'], []),
        IF(
            raw_unit_price IS NOT NULL AND TRIM(raw_unit_price) != '' AND unit_price_raw IS NULL,
            ['UNPARSEABLE_UNIT_PRICE'],
            []
        ),
        IF(unit_price_raw <= 0, ['NON_POSITIVE_UNIT_PRICE'], []),
        IF(raw_line_amount IS NULL, ['NULL_AMOUNT'], []),
        IF(raw_line_amount IS NOT NULL AND TRIM(raw_line_amount) = '', ['BLANK_AMOUNT'], []),
        IF(
            raw_line_amount IS NOT NULL
            AND TRIM(raw_line_amount) != ''
            AND line_net_amount_raw IS NULL,
            ['UNPARSEABLE_AMOUNT'],
            []
        ),
        IF(line_net_amount_raw < 0, ['NEGATIVE_AMOUNT'], []),
        IF(line_net_amount_raw = 0, ['ZERO_AMOUNT'], []),
        IF(
            line_net_amount_raw > 1000 AND line_net_amount_raw / 100 BETWEEN 1 AND 500,
            ['CENTS_CONVERTED'],
            []
        )
    ), '|') AS cleaning_flags
FROM `kupferkanne-2026.sales.stg_items_intake`;

-- ORDERS VALIDATED -------------------------------------------------------------
DROP TABLE IF EXISTS `kupferkanne-2026.sales.stg_orders_validated`;

CREATE TABLE `kupferkanne-2026.sales.stg_orders_validated`
CLUSTER BY customer_id, order_id AS
WITH ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY order_id
            ORDER BY source_month DESC, row_id ASC
        ) AS dedup_rank
    FROM `kupferkanne-2026.sales.stg_orders_cleaned`
    WHERE
        order_id IS NOT NULL
        AND customer_id IS NOT NULL
        AND order_date IS NOT NULL
)

SELECT
    order_id,
    customer_id,
    order_date,
    order_discount_pct,
    basket_item_count,
    source_month,
    cleaning_flags
FROM ranked
WHERE dedup_rank = 1;

-- ITEMS VALIDATED --------------------------------------------------------------
CREATE OR REPLACE TABLE `kupferkanne-2026.sales.stg_items_validated`
CLUSTER BY order_id, product_id AS
WITH ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY order_id, product_id
            ORDER BY source_month DESC, row_id ASC
        ) AS dedup_rank
    FROM `kupferkanne-2026.sales.stg_items_cleaned`
    WHERE
        order_id IS NOT NULL
        AND product_id IS NOT NULL
        AND quantity IS NOT NULL
        AND unit_price IS NOT NULL
        AND line_net_amount IS NOT NULL
)

SELECT
    order_id,
    product_id,
    quantity,
    unit_price,
    line_net_amount,
    source_month,
    cleaning_flags
FROM ranked
WHERE dedup_rank = 1;

-- CLEANING LOG -----------------------------------------------------------------
CREATE OR REPLACE TABLE `kupferkanne-2026.sales.cleaning_log` AS
WITH
orders_intake AS (SELECT COUNT(*) AS n FROM `kupferkanne-2026.sales.stg_orders_intake`),

items_intake AS (SELECT COUNT(*) AS n FROM `kupferkanne-2026.sales.stg_items_intake`),

orders_validated AS (SELECT COUNT(*) AS n FROM `kupferkanne-2026.sales.stg_orders_validated`),

items_validated AS (SELECT COUNT(*) AS n FROM `kupferkanne-2026.sales.stg_items_validated`),

order_flags AS (
    SELECT
        flag,
        COUNT(*) AS cnt,
        'orders' AS stream_type
    FROM `kupferkanne-2026.sales.stg_orders_cleaned`,
        UNNEST(IF(cleaning_flags = '', ['CLEAN'], SPLIT(cleaning_flags, '|'))) AS flag
    GROUP BY flag
),

item_flags AS (
    SELECT
        flag,
        COUNT(*) AS cnt,
        'items' AS stream_type
    FROM `kupferkanne-2026.sales.stg_items_cleaned`,
        UNNEST(IF(cleaning_flags = '', ['CLEAN'], SPLIT(cleaning_flags, '|'))) AS flag
    GROUP BY flag
),

all_flags AS (
    SELECT * FROM order_flags
    UNION ALL
    SELECT * FROM item_flags
),

entries AS (
    SELECT
        0 AS entry_order,
        'PIPELINE OVERVIEW' AS rule_name,
        CONCAT(
            'Orders: ',
            CAST((SELECT n FROM orders_intake) AS STRING),
            ' intake -> ',
            CAST((SELECT n FROM orders_validated) AS STRING),
            ' validated (',
            CAST(
                ROUND(
                    SAFE_DIVIDE((SELECT n FROM orders_validated), (SELECT n FROM orders_intake))
                    * 100,
                    2
                ) AS STRING
            ),
            '% retention). ',
            'Items: ',
            CAST((SELECT n FROM items_intake) AS STRING),
            ' intake -> ',
            CAST((SELECT n FROM items_validated) AS STRING),
            ' validated (',
            CAST(
                ROUND(
                    SAFE_DIVIDE((SELECT n FROM items_validated), (SELECT n FROM items_intake))
                    * 100,
                    2
                ) AS STRING
            ),
            '% retention).'
        ) AS finding
    UNION ALL
    SELECT
        ROW_NUMBER() OVER (ORDER BY stream_type, flag) AS entry_order,
        CONCAT(stream_type, ': ', flag) AS rule_name,
        CONCAT(CAST(cnt AS STRING), ' rows flagged in ', stream_type, ' stream.') AS finding
    FROM all_flags
    WHERE flag != 'CLEAN'
)

SELECT *
FROM entries
ORDER BY entry_order;

SELECT *  -- noqa: AM04
FROM `kupferkanne-2026.sales.cleaning_log`
ORDER BY entry_order;

SELECT
    'Orders intake' AS stage_name,
    COUNT(*) AS rows_count
FROM `kupferkanne-2026.sales.stg_orders_intake`
UNION ALL
SELECT
    'Orders validated',
    COUNT(*)
FROM `kupferkanne-2026.sales.stg_orders_validated`
UNION ALL
SELECT
    'Items intake',
    COUNT(*)
FROM `kupferkanne-2026.sales.stg_items_intake`
UNION ALL
SELECT
    'Items validated',
    COUNT(*)
FROM `kupferkanne-2026.sales.stg_items_validated`;
