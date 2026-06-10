-- ============================================================================
-- STEP 00.1: STANDARDISE LOOKUP TABLES
-- ============================================================================
-- Purpose:
--   Expose canonical, analytics-friendly lookup views without mutating raw
--   source tables. This is the semantic contract used by downstream SQL.
--
-- Outputs:
--   kupferkanne-2026.sales.v_dim_customers_std
--   kupferkanne-2026.sales.v_dim_products_std
-- ============================================================================

CREATE OR REPLACE VIEW `kupferkanne-2026.sales.v_dim_customers_std` AS
SELECT
    NULLIF(TRIM(CAST(CustomerID AS STRING)), '') AS customer_id,
    SAFE_CAST(NULLIF(TRIM(CAST(SignupDate AS STRING)), '') AS DATE) AS signup_date,
    NULLIF(TRIM(CAST(CustomerArchetype AS STRING)), '') AS customer_archetype,
    NULLIF(TRIM(CAST(FirstName AS STRING)), '') AS first_name,
    NULLIF(TRIM(CAST(LastName AS STRING)), '') AS last_name,
    ARRAY_TO_STRING(
        ARRAY(
            SELECT part
            FROM
                UNNEST([
                    NULLIF(TRIM(CAST(FirstName AS STRING)), ''),
                    NULLIF(TRIM(CAST(LastName AS STRING)), '')
                ]) AS part
            WHERE part IS NOT NULL
        ),
        ' '
    ) AS full_name,
    NULLIF(TRIM(CAST(Email AS STRING)), '') AS email,
    NULLIF(TRIM(CAST(Phone AS STRING)), '') AS phone,
    NULLIF(TRIM(CAST(Country AS STRING)), '') AS country,
    NULLIF(TRIM(CAST(State AS STRING)), '') AS state,
    NULLIF(TRIM(CAST(City AS STRING)), '') AS city,
    NULLIF(TRIM(CAST(Address AS STRING)), '') AS address
FROM `kupferkanne-2026.sales.dim_customers`;

CREATE OR REPLACE VIEW `kupferkanne-2026.sales.v_dim_products_std` AS
SELECT
    NULLIF(TRIM(CAST(ProductID AS STRING)), '') AS product_id,
    NULLIF(TRIM(CAST(ProductName AS STRING)), '') AS product_name,
    NULLIF(TRIM(CAST(ProductCategory AS STRING)), '') AS product_category,
    NULLIF(TRIM(CAST(Brand AS STRING)), '') AS brand,
    SAFE_CAST(NULLIF(TRIM(CAST(RetailPrice AS STRING)), '') AS NUMERIC) AS retail_price,
    SAFE_CAST(NULLIF(TRIM(CAST(UnitCost AS STRING)), '') AS NUMERIC) AS unit_cost,
    SAFE_CAST(NULLIF(TRIM(CAST(MarginPct AS STRING)), '') AS NUMERIC) AS margin_pct
FROM `kupferkanne-2026.sales.dim_products`;
