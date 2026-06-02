# 0005 – Dual-Grain Fact Model (Order + Line)

**Status**: Accepted  
**Date**: 2026-05-11

## Context

The dashboard needs to answer questions at two grains: **order-grain** (revenue, customer segmentation, country breakdown – one row per order) and **line-grain** (product performance, brand mix, category trends – one row per line item per order).

A single-grain fact table forces awkward compromises. Storing only at line-grain means revenue measures must divide by basket size to avoid double-counting; storing only at order-grain loses product detail entirely. Mixed measures over a single fact silently produce wrong numbers when a user drags a product attribute onto an order-grain visualisation.

## Decision

Maintain **two curated fact objects**, one per grain:

- `sales_curated` – order-grain (~169K rows). Used by PBI pages 1 (Executive), 2 (Segments), 4 (Churn), 5 (Regional), 6 (Drillthrough).
- `v_items_for_bi` – line-grain view (~275K rows). Used by PBI page 3 (Products).

Each grain has its own measure namespace enforced by convention:

- `[Total Revenue]`, `[Total Orders]`, `[Total Customers]`, `[Total Profit]` – order-grain.
- `[Line Revenue]`, `[Line Quantity]`, `[Line Margin %]` – line-grain.

The naming rule lets a reader immediately tell which grain is being aggregated, and lets a reviewer catch grain-mixing mistakes at code-review time.

## Consequences

- Power BI semantic model has two fact tables, each with its own relationship set to dimensions.
- Six order-grain measures and three line-grain measures explicitly written.
- Grain reconciliation measure documents that `SUM([Line Revenue]) ≈ SUM([Total Revenue])` within a small rounding tolerance.
- The `[Total *]` vs `[Line *]` naming is consistent across SQL view comments, DAX measures, and `measures.md`.

## Alternatives Considered

- **Single line-grain fact only** – rejected: every order-level measure would need a `DISTINCTCOUNT(OrderID)` workaround, and customer-segmentation joins become awkward.
- **Single order-grain fact only** – rejected: no product detail possible at all; entire Product page would be unbuildable.
- **One fact, with a degenerate "level" column** – rejected: encourages grain-mixing bugs; SQLBI strongly recommends separate facts when grains genuinely differ.
