# 0015 – Warehouse Table Retention

**Status**: Accepted  
**Date**: 2026-09-07  

## Context

The warehouse holds the curated star schema, the staging stream that produces it, and the audit tables that document the cleaning run. Power BI reads it in Import mode, and the SQL pipeline is re-run on demand rather than on a schedule, so the interval between runs is open-ended.

[ADR 0002](0002-bigquery-as-data-warehouse.md) selected BigQuery and recorded the sandbox tier as sufficient for the workload. That tier applies a fixed 60-day default table expiration to every dataset and does not allow it to be lifted, so a dataset held under it carries an expiry that removes pipeline tables between runs. The warehouse has to retain its tables until the next run replaces them.

## Decision

Run the BigQuery project with billing enabled, and hold the `sales` dataset with no default table expiration and no default partition expiration.

Retention is a property of the dataset, not of any individual script. The pipeline creates and replaces tables; nothing in it sets or relies on an expiry.

## Consequences

- Warehouse tables persist between pipeline runs. A Power BI refresh reads the tables left by the last run rather than depending on how recently that run happened.
- Enabling billing lifts the sandbox tier's restrictions, including the fixed default expiration. It does not by itself introduce cost: the free monthly allowances of 1 TB of query processing and 10 GB of storage still apply.
- Measured against those allowances at the date of this record, a full pipeline run over the eleven `sql/` scripts processes about 0.36 GB, and the dataset occupies about 0.24 GB across 113 objects. Both scale with the source data rather than with the number of runs.
- A billing-enabled project is a prerequisite for standing the warehouse up. The reproduction steps in [README.md](../../README.md) state it.
- The loader (`scripts/upload_to_bigquery_schema_enforced.py`) sets no expiration on a dataset it creates, and reports when the dataset it targets already carries one.

## Alternatives Considered

- **Remain on the sandbox tier and re-run the pipeline inside every 60-day window** – rejected. Retention would depend on run cadence, and a missed window empties the warehouse with no signal until a query or a refresh fails.
- **Set an explicit long expiration per table in the DDL** – rejected. It spreads a dataset-level property across eleven scripts, where each new table is an opportunity to omit it.
- **Export the curated tables to Cloud Storage and reload on demand** – rejected. It adds a second storage system and a restore step to cover what one dataset setting already covers.
