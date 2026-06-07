# 0013 – Unified Segment Dimension

**Status**: Accepted  
**Date**: 2026-06-07  
**Supersedes**: [ADR 0010](0010-segment-dimensions-separation.md)  

## Context

[ADR 0010](0010-segment-dimensions-separation.md) modelled the segment as two separate model-defined dimensions: one carrying sort order and color (the presentation concern), the other carrying the action playbook – email cadence, loyalty tier, discount approach, budget allocation (the prescription concern) – joined one-to-one on the segment label. The separation kept editorial playbook changes from perturbing sort and color, at the cost of a dimension-to-dimension snowflake link.

In the single-direction topology ([ADR 0012](0012-single-direction-customer-topology.md)), that inter-dimension link is the one remaining relationship that is neither fact-to-dimension nor part of the customer chain. Both dimensions are model-defined, fixed at six rows (one per segment), and edited as code rather than maintained as live data.

## Decision

Merge the two segment dimensions into a single model-defined dimension, `dim_Segment`, built with a `DATATABLE` expression. The unified table holds, per segment, the sort order, the color, and the full action playbook in one six-row dimension. The customer dimension relates many-to-one and single-direction to `dim_Segment`.

## Consequences

- The dimension-to-dimension link is removed. The model carries one segment dimension on a single-direction relationship to the customer dimension, consistent with the rest of the topology.
- Sort order and color remain stable across every page. The Sort By Column binding and the color column are set once on `dim_Segment` and inherited downstream, exactly as before.
- The action playbook and the presentation attributes now share a row. For a six-row, code-defined dimension this coupling is immaterial: an edit is a one-line change in the `DATATABLE` expression under version control, not a row edit in maintained data, so the lifecycle-independence concern that motivated the split no longer carries weight.
- Defining the dimension entirely in a `DATATABLE` expression removes a dependency on an external query for the playbook attributes, and with it a class of refresh-time error that the separate playbook table was exposed to.
- One dimension is less model surface than two. Cardinality is unchanged at six rows.

## Alternatives Considered

- **Retain two separate segment dimensions** ([ADR 0010](0010-segment-dimensions-separation.md)) – rejected. The separation buys lifecycle independence between presentation and prescription, which is valuable for live, maintained data but immaterial for a six-row dimension defined as code. It leaves a dimension-to-dimension link that the single-direction topology would otherwise carry as its only non-conformed relationship.
- **Surface the playbook on the customer-grain analytic outputs** – rejected, on the same grounds given in [ADR 0010](0010-segment-dimensions-separation.md): it would repeat the playbook across every customer row and tie it to the analytic lifecycle, with no per-customer variation to justify the cost.
