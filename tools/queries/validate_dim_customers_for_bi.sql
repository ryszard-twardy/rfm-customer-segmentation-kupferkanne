-- FILENAME: validate_dim_customers_for_bi.sql
-- ============================================================================
-- Validation suite for v_dim_customers_for_bi (see sql/04_5_*).
-- Read-only. Run AFTER the view DDL has been applied to BigQuery.
-- ============================================================================
-- Companion to sql/04_5_dim_customers_for_bi_kupferkanne_2026.sql.
-- Four diagnostics:
--   1. Grain parity vs v_dim_customers_std (no fan-out).
--   2. One row per CustomerID on the new view.
--   3. NULL-segment count (customers without orders).
--   4. Column inventory for parity inspection against the two source views.
-- ============================================================================

-- CHECK 1: grain parity with v_dim_customers_std.
-- The LEFT JOIN must not fan out; both inputs are customer-grain.
-- Expected: bi_dim_rows == std_dim_rows; row_delta == 0.
SELECT
    (SELECT COUNT(*) FROM `kupferkanne-2026.sales.v_dim_customers_for_bi`) AS bi_dim_rows,
    (SELECT COUNT(*) FROM `kupferkanne-2026.sales.v_dim_customers_std`) AS std_dim_rows,
    (SELECT COUNT(*) FROM `kupferkanne-2026.sales.v_dim_customers_for_bi`)
    - (SELECT COUNT(*) FROM `kupferkanne-2026.sales.v_dim_customers_std`) AS row_delta;

-- CHECK 2: one row per customer on the new view.
-- Expected: total_rows == distinct_customers; dup_delta == 0.
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT CustomerID) AS distinct_customers,
    COUNT(*) - COUNT(DISTINCT CustomerID) AS dup_delta
FROM `kupferkanne-2026.sales.v_dim_customers_for_bi`;

-- CHECK 3: customers with no RFM row (no orders) and therefore NULL segment.
-- Reports an integer; a non-zero result is expected if there are master
-- customers with no transactions in the data window.
SELECT
    COUNTIF(segment IS NULL) AS null_segment_customers,
    COUNTIF(segment IS NOT NULL) AS scored_customers,
    COUNT(*) AS total_customers
FROM `kupferkanne-2026.sales.v_dim_customers_for_bi`;

-- CHECK 4: column inventory of the new view.
-- Confirms the verbatim union of v_dim_customers_std columns plus the
-- v_rfm_for_bi columns, minus the four case-insensitive collisions that
-- v_rfm_for_bi shares with v_dim_customers_std (customer_id, country, state,
-- city). See sql/04_5_* header for the rationale.
SELECT
    column_name,
    data_type,
    ordinal_position
FROM `kupferkanne-2026.sales.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'v_dim_customers_for_bi'
ORDER BY ordinal_position;
