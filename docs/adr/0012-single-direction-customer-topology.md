# 0012 – Single-Direction Customer Topology

**Status**: Accepted  
**Date**: 2026-06-07  
**Supersedes**: [ADR 0011](0011-bidirectional-customer-satellite-relationship.md)  

## Context

The model previously carried a customer-grain analytic satellite holding the per-customer RFM outputs – recency, frequency, monetary, health score, segment label – related many-to-one to the customer dimension. The segment slicer lived on that satellite.

Under single-direction cross-filtering from satellite to dimension, a segment selection on the satellite had no path to the order-grain fact, so the order-grain KPIs (revenue, profit, order counts) stayed unfiltered. [ADR 0011](0011-bidirectional-customer-satellite-relationship.md) resolved this by setting the satellite-to-dimension relationship to bidirectional, and explicitly queued a review of whether a single-direction alternative could preserve the same filter propagation, gated by a VertiPaq Analyzer baseline scan.

That review is now concluded, in favour of a single-direction topology.

## Decision

Retire the analytic satellite as a relationship-bearing table and surface the segment on the customer dimension itself. The customer dimension relates many-to-one and single-direction to a model-defined segment dimension; the order-grain fact and the line-grain item view relate many-to-one and single-direction to the customer dimension.

A segment selection now filters the segment dimension, propagates to the customer dimension, and from there to the order-grain fact. The order-grain KPIs filter correctly on the executive and segment pages, with no bidirectional cross-filter anywhere in the model.

## Consequences

- The segment slicer filters order-grain measures correctly on the executive and segment pages, by single-direction propagation alone. The pages no longer depend on a bidirectional exception to return correct figures.
- Best Practice Analyzer no longer flags a bidirectional cross-filter on this model. The documented exception carried in [ADR 0011](0011-bidirectional-customer-satellite-relationship.md) is removed rather than maintained indefinitely.
- Filter paths are unambiguous. Every relationship is many-to-one and single-direction, so there is a single propagation path from any dimension to the fact tables.
- The per-customer RFM outputs remain available for analysis, but they no longer sit on a relationship-bearing satellite carrying its own slicer. The segment that drives report filtering lives on the customer dimension and its conformed segment dimension.
- Removing the satellite from the relationship graph also removes the dimension-to-dimension link that the separate segment dimensions required; see [ADR 0013](0013-unified-segment-dimension.md).

## Alternatives Considered

- **Retain the bidirectional satellite relationship** ([ADR 0011](0011-bidirectional-customer-satellite-relationship.md)) – rejected. It returns correct figures but carries a Best Practice Analyzer anti-pattern as a standing documented exception and leaves a second filter path into the customer dimension. The single-direction topology meets the same requirement without the exception.
- **Measure-side propagation via `CALCULATE` and `TREATAS`** – rejected. It transfers the segment filter at measure-evaluation time while leaving the relationship single-direction. It works, but it spreads the pattern across every order-grain measure consumed on the affected pages, adding measure complexity for no structural benefit once the segment lives on the customer dimension.
