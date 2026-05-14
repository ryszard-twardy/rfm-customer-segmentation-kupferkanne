-- ============================================================================
-- STEP 00: RAW DATA QUALITY AUDIT
-- ============================================================================
-- Purpose:
--   Audit raw monthly fact shards and raw dimension tables before any
--   standardisation or cleaning. This step is deliberately read-only.
--
-- Design notes:
--   1. Header/schema compliance is checked explicitly via INFORMATION_SCHEMA.
--   2. Wildcard fact reads are used only when required columns are present in
--      every shard and no physical type drift is detected across required
--      columns. If the schema contract is broken, the script does not crash,
--      it records the contract issue and skips value-level checks that depend
--      on the broken source.
--   3. Lookup-table key checks are also guarded, so the script remains usable
--      even if a raw dimension header is wrong.
--
-- Output:
--   kupferkanne-2026.sales.data_quality_audit_raw
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

DECLARE orders_contract_ok BOOL;
DECLARE items_contract_ok BOOL;
DECLARE dim_customers_key_ok BOOL;
DECLARE dim_products_key_ok BOOL;

DECLARE orders_source_sql STRING;
DECLARE items_source_sql STRING;
DECLARE dim_customers_key_sql STRING;
DECLARE dim_products_key_sql STRING;
DECLARE dim_customers_profile_sql STRING;
DECLARE dim_products_profile_sql STRING;
DECLARE orders_contract_ok_sql STRING;
DECLARE items_contract_ok_sql STRING;
DECLARE dim_customers_key_ok_sql STRING;
DECLARE dim_products_key_ok_sql STRING;

SET orders_contract_ok = (
    WITH order_tables AS (
        SELECT table_name
        FROM `kupferkanne-2026.sales.INFORMATION_SCHEMA.TABLES`
        WHERE
            table_type = 'BASE TABLE'
            AND table_name LIKE 'orders20%'
            AND REGEXP_EXTRACT(table_name, r'(\d{6})$') BETWEEN start_suffix AND end_suffix
    ),

    expected AS (
        SELECT 'OrderID' AS column_name
        UNION ALL
        SELECT 'CustomerID'
        UNION ALL
        SELECT 'OrderDate'
        UNION ALL
        SELECT 'OrderDiscountPct'
        UNION ALL
        SELECT 'BasketItemCount'
    ),

    missing_required AS (
        SELECT
            ot.table_name,
            e.column_name
        FROM order_tables AS ot
        CROSS JOIN expected AS e
        LEFT JOIN `kupferkanne-2026.sales.INFORMATION_SCHEMA.COLUMNS` AS c
            ON
                ot.table_name = c.table_name
                AND e.column_name = c.column_name
        WHERE c.column_name IS NULL
    ),

    type_drift AS (
        SELECT column_name
        FROM `kupferkanne-2026.sales.INFORMATION_SCHEMA.COLUMNS`
        WHERE
            table_name LIKE 'orders20%'
            AND REGEXP_EXTRACT(table_name, r'(\d{6})$') BETWEEN start_suffix AND end_suffix
            AND column_name IN (
                'OrderID', 'CustomerID', 'OrderDate', 'OrderDiscountPct', 'BasketItemCount'
            )
        GROUP BY column_name
        HAVING COUNT(DISTINCT data_type) > 1
    )

    SELECT
        (SELECT COUNT(*) FROM missing_required) = 0
        AND (SELECT COUNT(*) FROM type_drift) = 0
);

SET items_contract_ok = (
    WITH item_tables AS (
        SELECT table_name
        FROM `kupferkanne-2026.sales.INFORMATION_SCHEMA.TABLES`
        WHERE
            table_type = 'BASE TABLE'
            AND table_name LIKE 'items20%'
            AND REGEXP_EXTRACT(table_name, r'(\d{6})$') BETWEEN start_suffix AND end_suffix
    ),

    expected AS (
        SELECT 'OrderID' AS column_name
        UNION ALL
        SELECT 'ProductID'
        UNION ALL
        SELECT 'Quantity'
        UNION ALL
        SELECT 'UnitPrice'
        UNION ALL
        SELECT 'LineNetAmount'
    ),

    missing_required AS (
        SELECT
            it.table_name,
            e.column_name
        FROM item_tables AS it
        CROSS JOIN expected AS e
        LEFT JOIN `kupferkanne-2026.sales.INFORMATION_SCHEMA.COLUMNS` AS c
            ON
                it.table_name = c.table_name
                AND e.column_name = c.column_name
        WHERE c.column_name IS NULL
    ),

    type_drift AS (
        SELECT column_name
        FROM `kupferkanne-2026.sales.INFORMATION_SCHEMA.COLUMNS`
        WHERE
            table_name LIKE 'items20%'
            AND REGEXP_EXTRACT(table_name, r'(\d{6})$') BETWEEN start_suffix AND end_suffix
            AND column_name IN ('OrderID', 'ProductID', 'Quantity', 'UnitPrice', 'LineNetAmount')
        GROUP BY column_name
        HAVING COUNT(DISTINCT data_type) > 1
    )

    SELECT
        (SELECT COUNT(*) FROM missing_required) = 0
        AND (SELECT COUNT(*) FROM type_drift) = 0
);

SET dim_customers_key_ok = EXISTS(
    SELECT 1
    FROM `kupferkanne-2026.sales.INFORMATION_SCHEMA.COLUMNS`
    WHERE
        table_name = 'dim_customers'
        AND column_name = 'CustomerID'
);

SET dim_products_key_ok = EXISTS(
    SELECT 1
    FROM `kupferkanne-2026.sales.INFORMATION_SCHEMA.COLUMNS`
    WHERE
        table_name = 'dim_products'
        AND column_name = 'ProductID'
);

SET orders_source_sql = IF(
    orders_contract_ok,
    """
  SELECT
    CAST(OrderID AS STRING) AS raw_order_id,
    CAST(CustomerID AS STRING) AS raw_customer_id,
    CAST(OrderDate AS STRING) AS raw_order_date,
    SAFE_CAST(NULLIF(TRIM(CAST(OrderDate AS STRING)), '') AS DATE) AS parsed_date,
    _TABLE_SUFFIX AS src
  FROM `kupferkanne-2026.sales.orders20*`
  WHERE _TABLE_SUFFIX BETWEEN '""" || start_suffix || """' AND '""" || end_suffix || ''''
  ''',
    '''
  SELECT
    CAST(NULL AS STRING) AS raw_order_id,
    CAST(NULL AS STRING) AS raw_customer_id,
    CAST(NULL AS STRING) AS raw_order_date,
    CAST(NULL AS DATE) AS parsed_date,
    CAST(NULL AS STRING) AS src
  WHERE FALSE
  '''
);

SET items_source_sql = IF(
    items_contract_ok,
    """
  SELECT
    CAST(OrderID AS STRING) AS raw_order_id,
    CAST(ProductID AS STRING) AS raw_product_id,
    CAST(LineNetAmount AS STRING) AS raw_amount,
    SAFE_CAST(NULLIF(TRIM(CAST(LineNetAmount AS STRING)), '') AS NUMERIC) AS parsed_amount,
    _TABLE_SUFFIX AS src
  FROM `kupferkanne-2026.sales.items20*`
  WHERE _TABLE_SUFFIX BETWEEN '""" || start_suffix || """' AND '""" || end_suffix || ''''
  ''',
    '''
  SELECT
    CAST(NULL AS STRING) AS raw_order_id,
    CAST(NULL AS STRING) AS raw_product_id,
    CAST(NULL AS STRING) AS raw_amount,
    CAST(NULL AS NUMERIC) AS parsed_amount,
    CAST(NULL AS STRING) AS src
  WHERE FALSE
  '''
);

SET dim_customers_key_sql = IF(
    dim_customers_key_ok,
    '''
  SELECT DISTINCT NULLIF(TRIM(CAST(CustomerID AS STRING)), '') AS id
  FROM `kupferkanne-2026.sales.dim_customers`
  WHERE NULLIF(TRIM(CAST(CustomerID AS STRING)), '') IS NOT NULL
  ''',
    '''
  SELECT CAST(NULL AS STRING) AS id WHERE FALSE
  '''
);

SET dim_products_key_sql = IF(
    dim_products_key_ok,
    '''
  SELECT DISTINCT NULLIF(TRIM(CAST(ProductID AS STRING)), '') AS id
  FROM `kupferkanne-2026.sales.dim_products`
  WHERE NULLIF(TRIM(CAST(ProductID AS STRING)), '') IS NOT NULL
  ''',
    '''
  SELECT CAST(NULL AS STRING) AS id WHERE FALSE
  '''
);

SET dim_customers_profile_sql = IF(
    dim_customers_key_ok,
    '''
  SELECT NULLIF(TRIM(CAST(CustomerID AS STRING)), '') AS customer_id
  FROM `kupferkanne-2026.sales.dim_customers`
  ''',
    '''
  SELECT CAST(NULL AS STRING) AS customer_id WHERE FALSE
  '''
);

SET dim_products_profile_sql = IF(
    dim_products_key_ok,
    '''
  SELECT NULLIF(TRIM(CAST(ProductID AS STRING)), '') AS product_id
  FROM `kupferkanne-2026.sales.dim_products`
  ''',
    '''
  SELECT CAST(NULL AS STRING) AS product_id WHERE FALSE
  '''
);

SET orders_contract_ok_sql = IF(orders_contract_ok, 'TRUE', 'FALSE');
SET items_contract_ok_sql = IF(items_contract_ok, 'TRUE', 'FALSE');
SET dim_customers_key_ok_sql = IF(dim_customers_key_ok, 'TRUE', 'FALSE');
SET dim_products_key_ok_sql = IF(dim_products_key_ok, 'TRUE', 'FALSE');

EXECUTE IMMEDIATE FORMAT(
    '''
CREATE OR REPLACE TABLE `kupferkanne-2026.sales.data_quality_audit_raw` AS
WITH
order_tables AS (
  SELECT table_name
  FROM `kupferkanne-2026.sales.INFORMATION_SCHEMA.TABLES`
  WHERE table_type = 'BASE TABLE'
    AND table_name LIKE 'orders20%%'
    AND REGEXP_EXTRACT(table_name, r'(\\d{6})$') BETWEEN '%s' AND '%s'
),
item_tables AS (
  SELECT table_name
  FROM `kupferkanne-2026.sales.INFORMATION_SCHEMA.TABLES`
  WHERE table_type = 'BASE TABLE'
    AND table_name LIKE 'items20%%'
    AND REGEXP_EXTRACT(table_name, r'(\\d{6})$') BETWEEN '%s' AND '%s'
),
expected_dim_customers AS (
  SELECT 'CustomerID' AS column_name UNION ALL
  SELECT 'SignupDate' UNION ALL
  SELECT 'CustomerArchetype' UNION ALL
  SELECT 'FirstName' UNION ALL
  SELECT 'LastName' UNION ALL
  SELECT 'Email' UNION ALL
  SELECT 'Phone' UNION ALL
  SELECT 'Country' UNION ALL
  SELECT 'State' UNION ALL
  SELECT 'City' UNION ALL
  SELECT 'Address'
),
expected_dim_products AS (
  SELECT 'ProductID' AS column_name UNION ALL
  SELECT 'ProductName' UNION ALL
  SELECT 'ProductCategory' UNION ALL
  SELECT 'Brand' UNION ALL
  SELECT 'RetailPrice' UNION ALL
  SELECT 'UnitCost' UNION ALL
  SELECT 'MarginPct'
),
expected_orders AS (
  SELECT 'OrderID' AS column_name UNION ALL
  SELECT 'CustomerID' UNION ALL
  SELECT 'OrderDate' UNION ALL
  SELECT 'OrderDiscountPct' UNION ALL
  SELECT 'BasketItemCount'
),
expected_items AS (
  SELECT 'OrderID' AS column_name UNION ALL
  SELECT 'ProductID' UNION ALL
  SELECT 'Quantity' UNION ALL
  SELECT 'UnitPrice' UNION ALL
  SELECT 'LineNetAmount'
),
dim_customer_cols AS (
  SELECT column_name
  FROM `kupferkanne-2026.sales.INFORMATION_SCHEMA.COLUMNS`
  WHERE table_name = 'dim_customers'
),
dim_product_cols AS (
  SELECT column_name
  FROM `kupferkanne-2026.sales.INFORMATION_SCHEMA.COLUMNS`
  WHERE table_name = 'dim_products'
),
order_cols AS (
  SELECT table_name, column_name, data_type
  FROM `kupferkanne-2026.sales.INFORMATION_SCHEMA.COLUMNS`
  WHERE table_name LIKE 'orders20%%'
    AND REGEXP_EXTRACT(table_name, r'(\\d{6})$') BETWEEN '%s' AND '%s'
),
item_cols AS (
  SELECT table_name, column_name, data_type
  FROM `kupferkanne-2026.sales.INFORMATION_SCHEMA.COLUMNS`
  WHERE table_name LIKE 'items20%%'
    AND REGEXP_EXTRACT(table_name, r'(\\d{6})$') BETWEEN '%s' AND '%s'
),
raw_orders AS (
  %s
),
raw_items AS (
  %s
),
dim_c AS (
  %s
),
dim_p AS (
  %s
),
dim_customers_profile AS (
  %s
),
dim_products_profile AS (
  %s
),
ob AS (SELECT COUNT(*) AS n FROM raw_orders),
ib AS (SELECT COUNT(*) AS n FROM raw_items),

c01 AS (
  SELECT 1 AS seq, 'dim_customers missing required columns' AS chk, 'dim_customers schema' AS col,
         COUNT(*) AS cnt,
         (SELECT COUNT(*) FROM expected_dim_customers) AS tot,
         'CRITICAL' AS sev,
         'Fix raw dimension headers before downstream standardisation' AS fix
  FROM expected_dim_customers e
  LEFT JOIN dim_customer_cols c USING (column_name)
  WHERE c.column_name IS NULL
),
c02 AS (
  SELECT 2 AS seq, 'dim_customers unexpected columns' AS chk, 'dim_customers schema' AS col,
         COUNT(*) AS cnt,
         (SELECT COUNT(*) FROM dim_customer_cols) AS tot,
         'LOW' AS sev,
         'Review whether extra raw columns should be documented or standardised' AS fix
  FROM dim_customer_cols c
  LEFT JOIN expected_dim_customers e USING (column_name)
  WHERE e.column_name IS NULL
),
c03 AS (
  SELECT 3 AS seq, 'dim_products missing required columns' AS chk, 'dim_products schema' AS col,
         COUNT(*) AS cnt,
         (SELECT COUNT(*) FROM expected_dim_products) AS tot,
         'CRITICAL' AS sev,
         'Fix raw dimension headers before downstream joins' AS fix
  FROM expected_dim_products e
  LEFT JOIN dim_product_cols c USING (column_name)
  WHERE c.column_name IS NULL
),
c04 AS (
  SELECT 4 AS seq, 'dim_products unexpected columns' AS chk, 'dim_products schema' AS col,
         COUNT(*) AS cnt,
         (SELECT COUNT(*) FROM dim_product_cols) AS tot,
         'LOW' AS sev,
         'Review whether extra raw columns should be documented or standardised' AS fix
  FROM dim_product_cols c
  LEFT JOIN expected_dim_products e USING (column_name)
  WHERE e.column_name IS NULL
),
c05 AS (
  SELECT 5 AS seq, 'orders shards missing required columns' AS chk, 'orders20* schema' AS col,
         COUNT(DISTINCT table_name) AS cnt,
         (SELECT COUNT(*) FROM order_tables) AS tot,
         'CRITICAL' AS sev,
         'Wildcard reads are unsafe until every shard exposes the required header set' AS fix
  FROM (
    SELECT ot.table_name
    FROM order_tables ot
    CROSS JOIN expected_orders e
    LEFT JOIN order_cols c
      ON c.table_name = ot.table_name
     AND c.column_name = e.column_name
    WHERE c.column_name IS NULL
  )
),
c06 AS (
  SELECT 6 AS seq, 'orders shards with physical type drift' AS chk, 'orders20* schema' AS col,
         COUNT(*) AS cnt,
         (SELECT COUNT(*) FROM expected_orders) AS tot,
         'CRITICAL' AS sev,
         'Reload shards with an enforced schema before using wildcard queries' AS fix
  FROM (
    SELECT column_name
    FROM order_cols
    WHERE column_name IN (SELECT column_name FROM expected_orders)
    GROUP BY column_name
    HAVING COUNT(DISTINCT data_type) > 1
  )
),
c07 AS (
  SELECT 7 AS seq, 'items shards missing required columns' AS chk, 'items20* schema' AS col,
         COUNT(DISTINCT table_name) AS cnt,
         (SELECT COUNT(*) FROM item_tables) AS tot,
         'CRITICAL' AS sev,
         'Wildcard reads are unsafe until every shard exposes the required header set' AS fix
  FROM (
    SELECT it.table_name
    FROM item_tables it
    CROSS JOIN expected_items e
    LEFT JOIN item_cols c
      ON c.table_name = it.table_name
     AND c.column_name = e.column_name
    WHERE c.column_name IS NULL
  )
),
c08 AS (
  SELECT 8 AS seq, 'items shards with physical type drift' AS chk, 'items20* schema' AS col,
         COUNT(*) AS cnt,
         (SELECT COUNT(*) FROM expected_items) AS tot,
         'CRITICAL' AS sev,
         'Reload shards with an enforced schema before using wildcard queries' AS fix
  FROM (
    SELECT column_name
    FROM item_cols
    WHERE column_name IN (SELECT column_name FROM expected_items)
    GROUP BY column_name
    HAVING COUNT(DISTINCT data_type) > 1
  )
),
c09 AS (
  SELECT 9 AS seq, 'NULL customer lookup key' AS chk, 'dim_customers.CustomerID' AS col,
         CASE WHEN %s THEN COUNTIF(customer_id IS NULL) ELSE NULL END AS cnt,
         (SELECT COUNT(*) FROM `kupferkanne-2026.sales.dim_customers`) AS tot,
         'HIGH' AS sev,
         CASE WHEN %s THEN 'Fix raw dimension keys before referential checks and standardisation' ELSE 'Skipped because required header is missing' END AS fix
  FROM dim_customers_profile
),
c10 AS (
  SELECT 10 AS seq, 'Duplicate customer lookup key' AS chk, 'dim_customers.CustomerID' AS col,
         CASE WHEN %s THEN COUNT(*) - COUNT(DISTINCT customer_id) ELSE NULL END AS cnt,
         (SELECT COUNT(*) FROM `kupferkanne-2026.sales.dim_customers`) AS tot,
         'HIGH' AS sev,
         CASE WHEN %s THEN 'Dimension keys should be unique' ELSE 'Skipped because required header is missing' END AS fix
  FROM dim_customers_profile
  WHERE customer_id IS NOT NULL
),
c11 AS (
  SELECT 11 AS seq, 'NULL product lookup key' AS chk, 'dim_products.ProductID' AS col,
         CASE WHEN %s THEN COUNTIF(product_id IS NULL) ELSE NULL END AS cnt,
         (SELECT COUNT(*) FROM `kupferkanne-2026.sales.dim_products`) AS tot,
         'HIGH' AS sev,
         CASE WHEN %s THEN 'Fix raw dimension keys before referential checks and joins' ELSE 'Skipped because required header is missing' END AS fix
  FROM dim_products_profile
),
c12 AS (
  SELECT 12 AS seq, 'Duplicate product lookup key' AS chk, 'dim_products.ProductID' AS col,
         CASE WHEN %s THEN COUNT(*) - COUNT(DISTINCT product_id) ELSE NULL END AS cnt,
         (SELECT COUNT(*) FROM `kupferkanne-2026.sales.dim_products`) AS tot,
         'HIGH' AS sev,
         CASE WHEN %s THEN 'Dimension keys should be unique' ELSE 'Skipped because required header is missing' END AS fix
  FROM dim_products_profile
  WHERE product_id IS NOT NULL
),
c13 AS (
  SELECT 13 AS seq, 'NULL OrderID' AS chk, 'orders.OrderID' AS col,
         CASE WHEN %s THEN COUNTIF(NULLIF(TRIM(raw_order_id), '') IS NULL) ELSE NULL END AS cnt,
         (SELECT n FROM ob) AS tot,
         'CRITICAL' AS sev,
         CASE WHEN %s THEN 'Excluded during cleaning because transaction key is missing' ELSE 'Skipped because orders wildcard contract is broken' END AS fix
  FROM raw_orders
),
c14 AS (
  SELECT 14 AS seq, 'NULL CustomerID' AS chk, 'orders.CustomerID' AS col,
         CASE WHEN %s THEN COUNTIF(NULLIF(TRIM(raw_customer_id), '') IS NULL) ELSE NULL END AS cnt,
         (SELECT n FROM ob) AS tot,
         'CRITICAL' AS sev,
         CASE WHEN %s THEN 'Excluded during cleaning because customer key is missing' ELSE 'Skipped because orders wildcard contract is broken' END AS fix
  FROM raw_orders
),
c15 AS (
  SELECT 15 AS seq, 'Orphan CustomerID' AS chk, 'orders.CustomerID' AS col,
         CASE WHEN %s AND %s THEN COUNTIF(NULLIF(TRIM(raw_customer_id), '') IS NOT NULL AND TRIM(raw_customer_id) NOT IN (SELECT id FROM dim_c)) ELSE NULL END AS cnt,
         (SELECT n FROM ob) AS tot,
         'HIGH' AS sev,
         CASE WHEN %s AND %s THEN 'Investigate referential integrity between orders and dim_customers' ELSE 'Skipped because source or lookup contract is broken' END AS fix
  FROM raw_orders
),
c16 AS (
  SELECT 16 AS seq, 'NULL OrderDate' AS chk, 'orders.OrderDate' AS col,
         CASE WHEN %s THEN COUNTIF(NULLIF(TRIM(raw_order_date), '') IS NULL) ELSE NULL END AS cnt,
         (SELECT n FROM ob) AS tot,
         'CRITICAL' AS sev,
         CASE WHEN %s THEN 'Excluded during cleaning because recency cannot be computed' ELSE 'Skipped because orders wildcard contract is broken' END AS fix
  FROM raw_orders
),
c17 AS (
  SELECT 17 AS seq, 'Unparseable OrderDate' AS chk, 'orders.OrderDate' AS col,
         CASE WHEN %s THEN COUNTIF(NULLIF(TRIM(raw_order_date), '') IS NOT NULL AND parsed_date IS NULL) ELSE NULL END AS cnt,
         (SELECT n FROM ob) AS tot,
         'CRITICAL' AS sev,
         CASE WHEN %s THEN 'SAFE_CAST to NULL during cleaning and exclude from validated orders' ELSE 'Skipped because orders wildcard contract is broken' END AS fix
  FROM raw_orders
),
c18 AS (
  SELECT 18 AS seq, 'Future OrderDate' AS chk, 'orders.OrderDate' AS col,
         CASE WHEN %s THEN COUNTIF(parsed_date > CURRENT_DATE()) ELSE NULL END AS cnt,
         (SELECT n FROM ob) AS tot,
         'MEDIUM' AS sev,
         CASE WHEN %s THEN 'Set to NULL during cleaning and exclude from validated orders' ELSE 'Skipped because orders wildcard contract is broken' END AS fix
  FROM raw_orders
),
c19 AS (
  SELECT 19 AS seq, 'Whitespace in order keys' AS chk, 'orders.OrderID + CustomerID' AS col,
         CASE WHEN %s THEN COUNTIF(raw_order_id != TRIM(raw_order_id) OR raw_customer_id != TRIM(raw_customer_id)) ELSE NULL END AS cnt,
         (SELECT n FROM ob) AS tot,
         'LOW' AS sev,
         CASE WHEN %s THEN 'Trim in cleaning intake' ELSE 'Skipped because orders wildcard contract is broken' END AS fix
  FROM raw_orders
),
c20 AS (
  SELECT 20 AS seq, 'Negative LineNetAmount' AS chk, 'items.LineNetAmount' AS col,
         CASE WHEN %s THEN COUNTIF(parsed_amount < 0) ELSE NULL END AS cnt,
         (SELECT n FROM ib) AS tot,
         'CRITICAL' AS sev,
         CASE WHEN %s THEN 'Exclude during cleaning because negative revenue is treated as miscoded returns' ELSE 'Skipped because items wildcard contract is broken' END AS fix
  FROM raw_items
),
c21 AS (
  SELECT 21 AS seq, 'Zero LineNetAmount' AS chk, 'items.LineNetAmount' AS col,
         CASE WHEN %s THEN COUNTIF(parsed_amount = 0) ELSE NULL END AS cnt,
         (SELECT n FROM ib) AS tot,
         'MEDIUM' AS sev,
         CASE WHEN %s THEN 'Exclude during cleaning as likely test or non-billable lines' ELSE 'Skipped because items wildcard contract is broken' END AS fix
  FROM raw_items
),
c22 AS (
  SELECT 22 AS seq, 'NULL LineNetAmount' AS chk, 'items.LineNetAmount' AS col,
         CASE WHEN %s THEN COUNTIF(NULLIF(TRIM(raw_amount), '') IS NULL) ELSE NULL END AS cnt,
         (SELECT n FROM ib) AS tot,
         'HIGH' AS sev,
         CASE WHEN %s THEN 'Exclude during cleaning because amount is unknown' ELSE 'Skipped because items wildcard contract is broken' END AS fix
  FROM raw_items
),
c23 AS (
  SELECT 23 AS seq, 'Unparseable LineNetAmount' AS chk, 'items.LineNetAmount' AS col,
         CASE WHEN %s THEN COUNTIF(NULLIF(TRIM(raw_amount), '') IS NOT NULL AND parsed_amount IS NULL) ELSE NULL END AS cnt,
         (SELECT n FROM ib) AS tot,
         'HIGH' AS sev,
         CASE WHEN %s THEN 'SAFE_CAST to NULL during cleaning and exclude from validated items' ELSE 'Skipped because items wildcard contract is broken' END AS fix
  FROM raw_items
),
c24 AS (
  SELECT 24 AS seq, 'Cents format suspicion' AS chk, 'items.LineNetAmount' AS col,
         CASE WHEN %s THEN COUNTIF(parsed_amount > 1000 AND parsed_amount / 100 BETWEEN 1 AND 500) ELSE NULL END AS cnt,
         (SELECT n FROM ib) AS tot,
         'HIGH' AS sev,
         CASE WHEN %s THEN 'Normalise by dividing by 100 during cleaning when this pattern is detected' ELSE 'Skipped because items wildcard contract is broken' END AS fix
  FROM raw_items
),
c25 AS (
  SELECT 25 AS seq, 'Orphan ProductID' AS chk, 'items.ProductID' AS col,
         CASE WHEN %s AND %s THEN COUNTIF(NULLIF(TRIM(raw_product_id), '') IS NOT NULL AND TRIM(raw_product_id) NOT IN (SELECT id FROM dim_p)) ELSE NULL END AS cnt,
         (SELECT n FROM ib) AS tot,
         'HIGH' AS sev,
         CASE WHEN %s AND %s THEN 'Investigate referential integrity between items and dim_products' ELSE 'Skipped because source or lookup contract is broken' END AS fix
  FROM raw_items
),
c26 AS (
  SELECT 26 AS seq, 'Whitespace in item keys' AS chk, 'items.OrderID + ProductID' AS col,
         CASE WHEN %s THEN COUNTIF(raw_order_id != TRIM(raw_order_id) OR raw_product_id != TRIM(raw_product_id)) ELSE NULL END AS cnt,
         (SELECT n FROM ib) AS tot,
         'LOW' AS sev,
         CASE WHEN %s THEN 'Trim in cleaning intake' ELSE 'Skipped because items wildcard contract is broken' END AS fix
  FROM raw_items
),
c27 AS (
  SELECT 27 AS seq, 'Duplicate line items' AS chk, 'items.OrderID + ProductID + source_month' AS col,
         CASE WHEN %s THEN COUNT(*) - COUNT(DISTINCT CONCAT(raw_order_id, '|', raw_product_id, '|', src)) ELSE NULL END AS cnt,
         (SELECT n FROM ib) AS tot,
         'HIGH' AS sev,
         CASE WHEN %s THEN 'Deduplicate during cleaning, keeping the latest shard occurrence' ELSE 'Skipped because items wildcard contract is broken' END AS fix
  FROM raw_items
  WHERE raw_order_id IS NOT NULL
),
c28 AS (
  SELECT 28 AS seq, 'dim_customers row count' AS chk, 'dim_customers' AS col,
         COUNT(*) AS cnt,
         COUNT(*) AS tot,
         'INFO' AS sev,
         'Reference row count for the raw lookup table' AS fix
  FROM `kupferkanne-2026.sales.dim_customers`
),
c29 AS (
  SELECT 29 AS seq, 'dim_products row count' AS chk, 'dim_products' AS col,
         COUNT(*) AS cnt,
         COUNT(*) AS tot,
         'INFO' AS sev,
         'Reference row count for the raw lookup table' AS fix
  FROM `kupferkanne-2026.sales.dim_products`
),
audit AS (
  SELECT * FROM c01 UNION ALL SELECT * FROM c02 UNION ALL SELECT * FROM c03 UNION ALL
  SELECT * FROM c04 UNION ALL SELECT * FROM c05 UNION ALL SELECT * FROM c06 UNION ALL
  SELECT * FROM c07 UNION ALL SELECT * FROM c08 UNION ALL SELECT * FROM c09 UNION ALL
  SELECT * FROM c10 UNION ALL SELECT * FROM c11 UNION ALL SELECT * FROM c12 UNION ALL
  SELECT * FROM c13 UNION ALL SELECT * FROM c14 UNION ALL SELECT * FROM c15 UNION ALL
  SELECT * FROM c16 UNION ALL SELECT * FROM c17 UNION ALL SELECT * FROM c18 UNION ALL
  SELECT * FROM c19 UNION ALL SELECT * FROM c20 UNION ALL SELECT * FROM c21 UNION ALL
  SELECT * FROM c22 UNION ALL SELECT * FROM c23 UNION ALL SELECT * FROM c24 UNION ALL
  SELECT * FROM c25 UNION ALL SELECT * FROM c26 UNION ALL SELECT * FROM c27 UNION ALL
  SELECT * FROM c28 UNION ALL SELECT * FROM c29
)
SELECT
  seq AS check_order,
  chk AS check_name,
  col AS source_column,
  sev AS severity,
  cnt AS issue_count,
  tot AS table_rows,
  ROUND(IF(tot > 0 AND cnt IS NOT NULL, 100.0 * cnt / tot, NULL), 3) AS pct_of_table,
  fix AS handling,
  CURRENT_TIMESTAMP() AS audit_run_at
FROM audit
ORDER BY seq
''',
    start_suffix, end_suffix,
    start_suffix, end_suffix,
    start_suffix, end_suffix,
    start_suffix, end_suffix,
    orders_source_sql,
    items_source_sql,
    dim_customers_key_sql,
    dim_products_key_sql,
    dim_customers_profile_sql,
    dim_products_profile_sql,
    dim_customers_key_ok_sql, dim_customers_key_ok_sql,
    dim_customers_key_ok_sql, dim_customers_key_ok_sql,
    dim_products_key_ok_sql, dim_products_key_ok_sql,
    dim_products_key_ok_sql, dim_products_key_ok_sql,
    orders_contract_ok_sql, orders_contract_ok_sql,
    orders_contract_ok_sql, orders_contract_ok_sql,
    orders_contract_ok_sql,
    dim_customers_key_ok_sql,
    orders_contract_ok_sql,
    dim_customers_key_ok_sql,
    orders_contract_ok_sql, orders_contract_ok_sql,
    orders_contract_ok_sql, orders_contract_ok_sql,
    orders_contract_ok_sql, orders_contract_ok_sql,
    orders_contract_ok_sql, orders_contract_ok_sql,
    items_contract_ok_sql, items_contract_ok_sql,
    items_contract_ok_sql, items_contract_ok_sql,
    items_contract_ok_sql, items_contract_ok_sql,
    items_contract_ok_sql, items_contract_ok_sql,
    items_contract_ok_sql, items_contract_ok_sql,
    items_contract_ok_sql, dim_products_key_ok_sql, items_contract_ok_sql, dim_products_key_ok_sql,
    items_contract_ok_sql, items_contract_ok_sql,
    items_contract_ok_sql, items_contract_ok_sql
);

SELECT
    check_order,
    severity,
    CASE
        WHEN issue_count IS NULL THEN CONCAT(check_name, ' – Skipped. ', handling)
        WHEN severity = 'INFO' THEN CONCAT(check_name, ' – ', CAST(issue_count AS STRING), ' rows.')
        WHEN issue_count = 0 THEN CONCAT(check_name, ' – No issues found.')
        ELSE CONCAT(
            'Found ', CAST(issue_count AS STRING), ' for ', check_name,
            IF(pct_of_table IS NULL, '', CONCAT(' (', CAST(pct_of_table AS STRING), '%)')),
            ' – ', handling
        )
    END AS finding
FROM `kupferkanne-2026.sales.data_quality_audit_raw`
ORDER BY check_order;
