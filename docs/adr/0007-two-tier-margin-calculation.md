# 0007 – Two-Tier Margin Calculation

**Status**: Accepted  
**Date**: 2026-05-11

## Context

Profit margin is shown on multiple dashboard pages: segment-level (Page 2), brand-level (Page 3), country-level (Page 5). The naïve approach – `AVG(margin_per_order)` – produces misleading numbers because it treats a €5 order and a €5,000 order as equally weighted in the segment average.

For a segment of 100 customers where 90 placed €5 orders at 80% margin and 10 placed €5,000 orders at 20% margin:

- `AVG(margin_per_order)` ≈ **74%** – but this is meaningless for P&L purposes.
- True margin = `SUM(profit) / SUM(revenue)` = (90·4 + 10·1,000) / (90·5 + 10·5,000) = **22.6%**.

The two numbers diverge dramatically. Reporting the wrong one in a customer-segment context misleads the reader about which segments are profitable.

## Decision

Use **weighted margin**: `SUM(profit) / SUM(revenue)`, calculated at the same grain as the aggregation context (segment, country, brand, product). This is implemented via DAX `DIVIDE(SUM([Profit]), SUM([Revenue]))` rather than `AVERAGE([margin])`.

For transparency, two complementary measures are exposed in the dashboard tooltip:

- `[Total Margin %]` – weighted, used for KPIs and segment-level summaries.
- `[Average Order Margin %]` – equal-weight, shown only in tooltip context for completeness.

## Consequences

- Segment-level margin in the dashboard reflects actual P&L contribution.
- Pages 2, 3, 5 all consistently use weighted margin in headlines.
- Finance stakeholders immediately recognise the distinction (and the choice).
- The "two-tier" framing – weighted by default, equal-weight available on demand – surfaces in the tooltip design.

## Alternatives Considered

- **Equal-weight average everywhere** – rejected: misleading, contradicts standard finance practice.
- **Only weighted, no equal-weight at all** – rejected: showing both side-by-side in the tooltip is a small cost and supports finance team trust in headline numbers.
- **Margin per customer (LTV-style)** – out of scope: would require a separate measure and conflate revenue-share with profitability.

Note (2026-06-09): report page numbering changed after this ADR – Customer Lifecycle Intelligence inserted at page 5; Regional Analysis is now page 6, Customer Drillthrough page 7. Canonical page list: methodology.md.
