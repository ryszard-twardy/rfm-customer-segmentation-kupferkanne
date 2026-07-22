# 0006 – RFM Segmentation with `NTILE(5)`

**Status**: Accepted  
**Date**: 2026-05-11

## Context

Customer segmentation is a core deliverable of this project. The chosen method needs to be transparent (a reviewer can read the SQL and immediately understand the segmentation logic), reproducible (same inputs → same segments, deterministically), and explainable to a non-technical stakeholder.

Three families of approaches were considered:

1. **Quantile-based scoring** (NTILE) – score each customer 1–5 on each RFM dimension by quintile.
2. **Clustering** – k-means or hierarchical clustering on standardised RFM features.
3. **Single composite score** – weighted formula collapsing R, F, M into one number.

## Decision

Use **`NTILE(5)` quintile-based scoring** per dimension, then sum into a composite score (3–15), then map to six segments by threshold bands.

```sql
SELECT
    CustomerID,
    NTILE(5) OVER (ORDER BY days_since_last DESC) AS r_score,
    NTILE(5) OVER (ORDER BY order_count)         AS f_score,
    NTILE(5) OVER (ORDER BY total_spend)         AS m_score
FROM customer_rfm_inputs;
```

Segments are derived from `r_score + f_score + m_score`:

| Composite | Segment | Action |
|---|---|---|
| 13–15 | Champions | Reward and cross-sell premium |
| 11–12 | Loyal Customers | Loyalty programme and early access |
| 9–10 | Potential Loyalists | Upsell and increase frequency |
| 7–8 | Recent Customers | Onboarding and second purchase push |
| 5–6 | At Risk | Win-back campaign and incentives |
| 3–4 | Hibernating | Deep discount or sunset |

**Recency anchor**: `MAX(OrderDate)` across the dataset, not `CURRENT_DATE()`. The dataset ends in March 2026; using current date would inflate every recency value uniformly and compress the high end of the distribution. The EDA view `eda_recency_distribution` confirmed that anchored recency has the expected spread.

## Consequences

- Pure SQL implementation, no Python or sklearn required.
- Thresholds are transparent – anyone can read the `NTILE` call and the score band.
- Segment sizes are roughly balanced by construction (NTILE forces equal bucket sizes).
- The composite score is monotonic against revenue contribution, verified via EDA.

## Alternatives Considered

- **k-means clustering** – rejected: clusters are not interpretable without inspection of centroids; thresholds aren't human-readable; results depend on initialisation seed.
- **Single composite formula** (e.g., `0.5*R + 0.3*F + 0.2*M`) – rejected: arbitrary weights, loses per-dimension information, harder to justify analytically.
- **`CURRENT_DATE()` as recency anchor** – rejected: distorts recency when the dataset is bounded in the past.
