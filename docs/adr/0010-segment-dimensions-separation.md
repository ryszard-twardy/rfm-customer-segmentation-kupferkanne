# 0010 – Segment Dimensions Separation

**Status**: Superseded by [ADR 0013](0013-unified-segment-dimension.md)  
**Date**: 2026-05-28  
**Superseded**: 2026-06-07  

## Context

RFM scoring assigns each customer to one of a small set of segment labels. Two distinct concerns attach to that label.

The first is presentation: a segment is an ordered, colorable categorical used for slicing, sorting, and consistent visual coloring across all report pages. The set is small and the order matters (Champions first, Hibernating last).

The second is prescription: each segment carries an action playbook – email cadence, loyalty tier, discount approach, budget allocation – maintained by marketing as the operational follow-up to the score. The playbook is editorial content with its own lifecycle; it changes as campaigns evolve, independently of how segments are rendered on a chart.

Treating these as a single attribute set would couple presentation to prescription. Adding a budget column would touch the same row as the sort order, and every visual that needs segment color would also load the full playbook.

## Decision

Model these as two separate model-defined dimensions, joined one-to-one and single-direction:

- `dim_SegmentOrder` – sort order plus segment color bridge. Provides the canonical sort sequence (used as Sort By Column on the segment attribute) and the canonical color palette (used for conditional formatting on visuals).
- `dim_SegmentActions` – action playbook. Holds the prescriptive columns marketing maintains.

The one-to-one link runs between `dim_SegmentActions` and `dim_SegmentOrder` on the segment label. It is a deliberate small snowflake between two model-defined dimensions, not a flattening of one onto the other.

## Consequences

- Sort order and color are stable across every page that uses the segment attribute. The Sort By Column binding is set once on `dim_SegmentOrder` and inherited everywhere downstream.
- The action playbook is maintained independently. Editing a discount approach or a budget allocation touches only `dim_SegmentActions` and does not perturb sort or color.
- The dimension-to-dimension link is one-to-one and single-direction. It is structurally distinct from a bidirectional cross-filter between a fact and a dimension and is not affected by the anti-pattern guidance Best Practice Analyzer applies to bidirectional cross-filtering.
- Two dimensions are slightly more model surface than one. The cost is small because both are model-defined (DATATABLE and Enter Data) with a fixed six-row cardinality.

## Alternatives Considered

- **Single combined segment dimension** – rejected. Mixes presentation (sort, color) with prescription (campaign actions). Editing the playbook risks perturbing sort or color, and consumers of segment color have to scan past playbook columns.
- **Denormalize action attributes onto the customer-grain fact view** – rejected. Repeats the playbook across every customer row, makes the playbook depend on the analytic satellite's lifecycle, and inflates the fact view with attributes that have no per-customer variation.
