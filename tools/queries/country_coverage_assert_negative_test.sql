-- FILENAME: country_coverage_assert_negative_test.sql
-- ============================================================================
-- Negative test for sql/06_country_coverage_assert_kupferkanne_2026.sql
-- (references: ADR 0003, ADR 0004). Read-only. Built to FAIL.
-- ============================================================================
-- Runs the three Step 06 assertions unchanged, with one fault injected per
-- run. Set the fault variable below; each fault must stop the script at the
-- check it targets, with that check's own message:
--   'empty_curated'         every curated order is removed    -> check 1
--     Country coverage: sales_curated holds no country
--   'extra_curated_country' a curated order with a country    -> check 2
--                           ('Atlantis') no segmented customer has
--     Country coverage: a country on a curated order is missing from
--     rfm_customer_segments
--   'segment_country_missing_from_dimension'                  -> check 3
--                           a segmented country ('Atlantis') the customer
--                           dimension lacks
--     Country coverage: rfm_customer_segments holds a country missing from
--     the customer dimension
--   'none'                  positive control: all three assertions pass
-- Any other error (syntax, permission, missing table) means the test did not
-- run; a pass with a fault set means the targeted check cannot fail, or that
-- 'Atlantis' is a real country in the tables. An unknown fault value stops
-- the script before the three coverage assertions. Run 'none' first: if it
-- fails, Step 06 fails on live data and the fault runs prove nothing.
--
-- Kept outside sql/ so that running the numbered scripts in order never runs
-- it. Keep the dimension DECLARE and the three country-coverage ASSERT
-- statements identical to Step 06.
-- ============================================================================

DECLARE fault STRING DEFAULT 'extra_curated_country';

DECLARE curated_countries ARRAY<STRING> DEFAULT (
    WITH curated AS (
        SELECT country
        FROM `kupferkanne-2026.sales.sales_curated`
        WHERE fault != 'empty_curated'
        UNION ALL
        SELECT 'Atlantis' AS country
        FROM UNNEST([fault]) AS injected
        WHERE injected = 'extra_curated_country'
    )

    SELECT ARRAY_AGG(DISTINCT country)
    FROM curated
    WHERE country IS NOT NULL
);

DECLARE segmented_countries ARRAY<STRING> DEFAULT (
    WITH segmented AS (
        SELECT primary_country
        FROM `kupferkanne-2026.sales.rfm_customer_segments`
        UNION ALL
        SELECT 'Atlantis' AS primary_country
        FROM UNNEST([fault]) AS injected
        WHERE injected = 'segment_country_missing_from_dimension'
    )

    SELECT ARRAY_AGG(DISTINCT primary_country)
    FROM segmented
    WHERE primary_country IS NOT NULL
);

DECLARE dimension_countries ARRAY<STRING> DEFAULT (
    SELECT ARRAY_AGG(DISTINCT country)
    FROM `kupferkanne-2026.sales.v_dim_customers_std`
    WHERE country IS NOT NULL
);

ASSERT fault IN (
    'none', 'empty_curated', 'extra_curated_country', 'segment_country_missing_from_dimension'
) AS 'Negative test: unknown fault value';

ASSERT COALESCE(ARRAY_LENGTH(curated_countries), 0) > 0
AS 'Country coverage: sales_curated holds no country';

ASSERT NOT EXISTS (
    SELECT country FROM UNNEST(curated_countries) AS country
    EXCEPT DISTINCT
    SELECT country FROM UNNEST(segmented_countries) AS country
) AS 'Country coverage: a country on a curated order is missing from rfm_customer_segments';

ASSERT NOT EXISTS (
    SELECT country FROM UNNEST(segmented_countries) AS country
    EXCEPT DISTINCT
    SELECT country FROM UNNEST(dimension_countries) AS country
) AS 'Country coverage: rfm_customer_segments holds a country missing from the customer dimension';
