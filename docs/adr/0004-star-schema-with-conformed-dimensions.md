# 0004 – Star Schema with Conformed Dimensions

**Status**: Accepted  
**Date**: 2026-05-11

## Context

The data model needs to serve two consumers: SQL analysis in BigQuery (RFM scoring, EDA, analytics marts) and Power BI in Import mode (six dashboard pages with 36+ DAX measures). The model needs to be easy to query, fast to aggregate, and resilient to growth.

Two main alternatives exist for dimensional modelling: classic Kimball star schema (one fact, many dimensions) and snowflake schema (normalised dimensions). For BI consumption, star schema is almost universally preferred.

## Decision

Adopt a **Kimball-style star schema** with two conformed dimensions (`dim_customers`, `dim_products`) shared across two fact tables (`orders20YYMM`, `items20YYMM`).

Conformed dimensions mean: `CustomerID` carries the same meaning whether joined to orders or to items; `ProductID` is consistent across all line-level facts. This enables drill-paths in Power BI (segment → customer → orders → line items) without the relationships becoming ambiguous.

Standardisation views (`v_dim_customers_std`, `v_dim_products_std`) wrap the raw dimensions and expose canonical field names and types. All downstream SQL queries the standardisation views, never the raw `dim_*` tables – so raw-schema changes are absorbed at one layer.

## Consequences

- Power BI relationships are direct one-to-many from dimension to fact.
- SQL joins are simple: `fact JOIN dim ON fact.CustomerID = dim.CustomerID`.
- Drill-through from segment → customer → orders works without ambiguity.
- Schema-shape concerns are isolated in standardisation views; analytical SQL remains stable across raw schema evolutions.

## Alternatives Considered

- **Snowflake schema** – rejected: extra joins for normalised attributes (e.g., separate brand/category tables) provide no benefit at this scale and slow Power BI's query folding.
- **One Big Table (OBT)** – rejected: loses the analytical clarity of separating "who" (dim) from "what happened" (fact); harder to maintain measures across grains.
- **Data Vault** – rejected: appropriate for enterprise-scale ingestion, overkill for a single-source analytics dataset at this scale.

Note (2026-06-09): report page numbering and counts changed after this ADR – 7 pages (Customer Lifecycle Intelligence inserted at page 5; Regional Analysis now page 6, Customer Drillthrough page 7); DAX measure count now 47. Canonical: methodology.md, measures.md.
