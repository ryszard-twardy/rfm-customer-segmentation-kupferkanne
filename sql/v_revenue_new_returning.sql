-- v_revenue_new_returning.sql
-- ADR: adr/0003 (pipeline order) + methodology.md (acquisition-month logic)
-- Monthly revenue split by acquisition status:
--   New       = revenue in a customer's first-purchase month
--   Returning = revenue in any later month

CREATE OR REPLACE VIEW `kupferkanne-2026.sales.v_revenue_new_returning` AS
WITH first_purchase AS (
    SELECT
        customer_id,
        DATE_TRUNC(MIN(order_date), MONTH) AS cohort_month
    FROM `kupferkanne-2026.sales.sales_curated`
    GROUP BY customer_id
)

SELECT
    DATE_TRUNC(s.order_date, MONTH) AS revenue_month,
    IF(
        DATE_TRUNC(s.order_date, MONTH) = f.cohort_month,
        'New',
        'Returning'
    ) AS customer_type,
    SUM(s.order_value) AS revenue,
    COUNT(DISTINCT s.customer_id) AS active_customers
FROM `kupferkanne-2026.sales.sales_curated` AS s
INNER JOIN first_purchase AS f USING (customer_id)
GROUP BY revenue_month, customer_type;

-- Validation: SUM(revenue) over all rows = [Total Revenue] baseline 8,531,365.52.
