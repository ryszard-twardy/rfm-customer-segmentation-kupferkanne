-- FILENAME: 04_5_dim_customers_for_bi_kupferkanne_2026.sql
-- ============================================================================
-- STEP 04.5: BI-FACING CUSTOMER DIMENSION
-- ============================================================================
-- Purpose:
--   Expose a single conformed BI-facing customer dimension that combines the
--   standardised customer master with the customer-grain RFM analytic outputs.
--   This view is intended to become Power BI's dim_Customer. With segment and
--   recency carried on the dimension itself, the segment slicer can propagate
--   dimension to fact in a single direction, retiring the need for a
--   bidirectional satellite relationship downstream.
--
-- Grain: one row per customer_id (parity with v_dim_customers_std).
--
-- Construction:
--   v_dim_customers_std LEFT JOIN v_rfm_for_bi on the customer key.
--   Both inputs are customer-grain, so the 1:1 LEFT JOIN preserves grain.
--   Customers without orders retain master attributes; RFM columns are NULL.
--
--   Projection uses s.*, r.* EXCEPT (...) so that any future column added to
--   either source view flows through automatically. No column lists to keep
--   in sync.
--
-- References:
--   ADR 0003 (pipeline order: this step depends on step 03 RFM outputs and
--     therefore must run after step 03).
--   ADR 0004 (conformed dimensions: this view is the BI-facing enriched
--     instance of the customer conformed dimension).
-- ============================================================================
-- EXCEPT list rationale:
--   BigQuery resolves identifiers case-insensitively, so columns that share a
--   name collide in the same SELECT list regardless of case. The two source
--   views share four such collisions:
--     * v_dim_customers_std.customer_id vs v_rfm_for_bi.customer_id
--       (the join key; identical values after the join).
--     * v_dim_customers_std.country / state / city vs v_rfm_for_bi.country /
--       state / city (customer master geo from the dimension vs
--       latest-order-derived geo from the RFM snapshot).
--   Keep the conformed-dimension casing and master geo from v_dim_customers_std;
--   drop the v_rfm_for_bi duplicates so the SELECT compiles.
-- ============================================================================

-- noqa: disable=AM04
-- AM04 disabled for this view only. Column count is intentionally
-- structural: s.* plus r.* EXCEPT (...) makes parity guaranteed by
-- construction, so new columns added to either source view flow through
-- without requiring this file to be edited in lockstep.
CREATE OR REPLACE VIEW `kupferkanne-2026.sales.v_dim_customers_for_bi`
OPTIONS (description = 'BI-facing conformed customer dimension joining standardized master attributes with RFM segment and recency; one row per customer.')  -- noqa: LT05
AS
SELECT
    s.*,
    r.* EXCEPT (customer_id, country, state, city)
FROM `kupferkanne-2026.sales.v_dim_customers_std` AS s
LEFT JOIN `kupferkanne-2026.sales.v_rfm_for_bi` AS r
    ON s.customer_id = r.customer_id;
-- noqa: enable=AM04
