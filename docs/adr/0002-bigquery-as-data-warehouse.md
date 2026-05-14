# 0002 – BigQuery as Data Warehouse

**Status**: Accepted  
**Date**: 2026-05-11

## Context

The project needs a cloud data warehouse to host the curated star schema, run the SQL pipeline, and serve Power BI in Import mode. Constraints: zero infrastructure overhead, free or near-free for ~440K records, dialect familiar enough that the code reads as production-grade.

## Decision

Use **Google BigQuery** with the GoogleSQL dialect. The project lives under one dataset (`kupferkanne-2026.sales`) containing 22 objects: 10 tables (audit, staging streams, curated facts, segmentation output) and 12 views (dimension standardisation, BI semantic layer, EDA, analytics marts).

## Consequences

- GoogleSQL idioms used throughout: `APPROX_QUANTILES`, `DATE_DIFF`, `FORMAT_DATE`, sharded-table wildcards (`orders20*`).
- BigQuery sandbox (1 TB/month query, 10 GB storage) covers the entire project without billing.
- Sharded fact tables (`orders20YYMM`, `items20YYMM`) enable wildcard scans without partition setup.
- Power BI connects via Google BigQuery connector with OAuth.
- `CLUSTER BY` used for staging tables; `PARTITION BY` avoided due to a conflict with window-function `PARTITION BY` clauses encountered during development (documented in project internal notes).

## Alternatives Considered

- **Snowflake** – rejected: free tier is time-limited; would expire mid-project.
- **PostgreSQL local** – rejected: doesn't match Kupferkanne's operational profile (cloud-native, serverless, zero infrastructure overhead) and lacks free-tier sharded-table semantics.
- **Databricks Free Edition** – considered but rejected: Lakehouse architecture is overkill for dimensional reporting at this scale and adds learning curve without proportional gain.
- **DuckDB** – used in parallel internal tooling but rejected here: not aligned with the hosted-warehouse operational model Kupferkanne required.
