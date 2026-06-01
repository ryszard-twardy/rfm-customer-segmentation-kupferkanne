# 0011 – Bidirectional Customer-Satellite Relationship

**Status**: Accepted  
**Date**: 2026-05-28

## Context

The model carries a customer-grain analytic satellite, `v_rfm_for_bi`, related many-to-one to the customer dimension `v_dim_customers_std`. The satellite holds the per-customer RFM scoring outputs – recency, frequency, monetary, health score, segment label – and is the home of the segment slicer used on the executive and segment pages.

Order-grain measures (revenue, profit, order counts) source from the order-grain fact `sales_curated`. The customer dimension is the conformed dimension shared between satellite and order fact.

A single-direction relationship from satellite to dimension propagates filters in one direction only: from the dimension into the satellite. A selection on the segment slicer, which sits on the satellite, would then have no path by which to reach the order-grain fact – the filter would not push down from satellite to dimension to fact. The segment slicer would slice satellite-grain visuals but leave the order-grain KPIs unfiltered, which is incorrect for the executive and segment pages.

## Decision

Set the cross-filter direction on the satellite-to-customer-dimension relationship to bidirectional. The relationship stays many-to-one in cardinality; only the cross-filter direction changes. With bidirectional cross-filtering, a segment selection on the satellite propagates to the customer dimension and from there to the order-grain fact, and the executive and segment pages return the correct filtered KPIs.

## Consequences

- The segment slicer correctly filters order-grain measures on the executive and segment pages. Without this, those pages would silently overstate revenue and profit under any segment selection.
- Best Practice Analyzer flags bidirectional cross-filter as a general anti-pattern because it can introduce ambiguous filter paths in models with multiple fact tables and multiple paths between dimensions. This instance is accepted as a deliberate, documented exception: the model carries a single analytic satellite over the customer dimension, the propagation requirement is explicit, and the surface where ambiguity could arise is bounded.
- The behaviour is local to the customer dimension. Other dimensions (`dim_Date`, the product dimension, the segment dimensions) carry single-direction cross-filter, so the bidirectional exception does not propagate.
- A review of whether a single-direction alternative can preserve the same filter-propagation requirement is queued for a later iteration. The review is gated by a VertiPaq Analyzer baseline scan; quantitative figures are pending that scan and are intentionally left unspecified here `[?]`.

## Alternatives Considered

- **Single-direction relationship with the segment surfaced as a customer-dimension column** – candidate, pending the queued review. The segment label would live on the customer dimension itself, and the satellite-to-dimension relationship would stay single-direction. The trade-off is that segment maintenance moves out of the satellite and the analytic satellite no longer carries its own slicer.
- **Measure-side approach via `CALCULATE` and `TREATAS`** – candidate, pending the queued review. The segment filter on the satellite would be transferred to the customer dimension and into the fact at measure-evaluation time, leaving the underlying relationship single-direction. The trade-off is added measure complexity and the need to apply the pattern consistently across every order-grain measure consumed on the affected pages.
- **Retain the current bidirectional relationship** – current state. Accepted on the grounds set out above.
