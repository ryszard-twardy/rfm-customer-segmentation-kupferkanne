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
    NULLIF(TRIM(CAST(CustomerID AS STRING)), '') AS CustomerID,
    SAFE_CAST(NULLIF(TRIM(CAST(SignupDate AS STRING)), '') AS DATE) AS SignupDate,
    NULLIF(TRIM(CAST(CustomerArchetype AS STRING)), '') AS CustomerArchetype,
    NULLIF(TRIM(CAST(FirstName AS STRING)), '') AS FirstName,
    NULLIF(TRIM(CAST(LastName AS STRING)), '') AS LastName,
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
    ) AS FullName,
    NULLIF(TRIM(CAST(Email AS STRING)), '') AS Email,
    NULLIF(TRIM(CAST(Phone AS STRING)), '') AS Phone,
    NULLIF(TRIM(CAST(Country AS STRING)), '') AS Country,
    NULLIF(TRIM(CAST(State AS STRING)), '') AS State,
    NULLIF(TRIM(CAST(City AS STRING)), '') AS City,
    NULLIF(TRIM(CAST(Address AS STRING)), '') AS Address
FROM `kupferkanne-2026.sales.dim_customers`;

CREATE OR REPLACE VIEW `kupferkanne-2026.sales.v_dim_products_std` AS
SELECT
    NULLIF(TRIM(CAST(ProductID AS STRING)), '') AS ProductID,
    NULLIF(TRIM(CAST(ProductName AS STRING)), '') AS ProductName,
    NULLIF(TRIM(CAST(ProductCategory AS STRING)), '') AS ProductCategory,
    NULLIF(TRIM(CAST(Brand AS STRING)), '') AS Brand,
    SAFE_CAST(NULLIF(TRIM(CAST(RetailPrice AS STRING)), '') AS NUMERIC) AS RetailPrice,
    SAFE_CAST(NULLIF(TRIM(CAST(UnitCost AS STRING)), '') AS NUMERIC) AS UnitCost,
    SAFE_CAST(NULLIF(TRIM(CAST(MarginPct AS STRING)), '') AS NUMERIC) AS MarginPct
FROM `kupferkanne-2026.sales.dim_products`;
