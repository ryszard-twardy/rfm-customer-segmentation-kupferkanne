-- ============================================================================
-- STEP 06: COUNTRY COVERAGE ASSERTION
-- ============================================================================
-- Purpose:
--   Stop the run if country coverage breaks between the curated orders, the
--   segmented output and the customer dimension. Read-only: three variables
--   and three ASSERT statements; no table is written.
--
-- Checks (each ASSERT fails with its own message):
--   1. Guard: sales_curated holds at least one country, so checks 2 and 3
--      cannot pass on an empty set. It also fires if no curated order
--      matches a customer with a country.
--   2. Every country on a curated order appears in rfm_customer_segments.
--      Holds by construction while v_dim_customers_std has one row per
--      customer: Step 03 builds one segment row per customer in
--      sales_curated and takes primary_country from that customer's latest
--      order, and every order of a customer then carries that customer's one
--      country. A duplicated customer key with two countries could break it;
--      the raw audit reports duplicate keys, this step does not assert
--      key uniqueness.
--   3. Every country in rfm_customer_segments appears in v_dim_customers_std.
--      Holds by construction: primary_country comes from that view through
--      sales_curated.
--   A NULL country is not a country and is left out on every side. The
--   reverse of check 3 (every dimension country is segmented) is not
--   asserted: it holds only while every country has a customer with an order.
--
-- Prerequisites:
--   Run Step 00.1 (v_dim_customers_std) and Step 03 (sales_curated,
--   rfm_customer_segments).
--
-- Negative test:
--   tools/queries/country_coverage_assert_negative_test.sql injects one
--   fault per check; each must stop the run at the check it targets.
--
-- References:
--   ADR 0003 (pipeline order). Numbered 06 so that it runs after every
--     object it reads: a 03_1 name would sort before 03_rfm and run too
--     early.
--   ADR 0004 (conformed dimensions: the segmented output carries only
--     countries of the customer dimension, check 3).
-- ============================================================================

DECLARE curated_countries ARRAY<STRING> DEFAULT (
    SELECT ARRAY_AGG(DISTINCT country)
    FROM `kupferkanne-2026.sales.sales_curated`
    WHERE country IS NOT NULL
);

DECLARE segmented_countries ARRAY<STRING> DEFAULT (
    SELECT ARRAY_AGG(DISTINCT primary_country)
    FROM `kupferkanne-2026.sales.rfm_customer_segments`
    WHERE primary_country IS NOT NULL
);

DECLARE dimension_countries ARRAY<STRING> DEFAULT (
    SELECT ARRAY_AGG(DISTINCT country)
    FROM `kupferkanne-2026.sales.v_dim_customers_std`
    WHERE country IS NOT NULL
);

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
