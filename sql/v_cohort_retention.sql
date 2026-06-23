-- v_cohort_retention.sql
-- ADR: adr/0003 (pipeline order) + methodology.md (cohort retention logic)
-- Retention rate by acquisition cohort x months since first purchase

CREATE OR REPLACE VIEW `kupferkanne-2026.sales.v_cohort_retention` AS
WITH first_purchase AS (
    SELECT
        customer_id,
        DATE_TRUNC(MIN(order_date), MONTH) AS cohort_month
    FROM `kupferkanne-2026.sales.sales_curated`
    GROUP BY customer_id
),

activity AS (
    SELECT
        s.customer_id,
        f.cohort_month,
        DATE_DIFF(DATE_TRUNC(s.order_date, MONTH), f.cohort_month, MONTH)
            AS months_since_acquisition
    FROM `kupferkanne-2026.sales.sales_curated` AS s
    INNER JOIN first_purchase AS f USING (customer_id)
),

cohort_size AS (
    SELECT
        cohort_month,
        COUNT(DISTINCT customer_id) AS cohort_customers
    FROM first_purchase
    GROUP BY cohort_month
)

SELECT
    a.cohort_month,
    a.months_since_acquisition,
    COUNT(DISTINCT a.customer_id) AS active_customers,
    c.cohort_customers,
    SAFE_DIVIDE(COUNT(DISTINCT a.customer_id), c.cohort_customers) AS retention_rate
FROM activity AS a
INNER JOIN cohort_size AS c USING (cohort_month)
GROUP BY a.cohort_month, a.months_since_acquisition, c.cohort_customers;

-- Validation: months_since_acquisition = 0 must return retention_rate = 1.0 for every cohort.
