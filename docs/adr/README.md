# Architecture Decision Records

This folder contains the key architecture decisions taken in the Kupferkanne project, recorded as Architecture Decision Records (ADRs). The format follows [Michael Nygard's template](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions): Context, Decision, Consequences, Alternatives.

ADRs are intentionally focused – they capture **strategic** decisions where there was a meaningful choice between alternatives, not every implementation detail. Each is short, dated, and frozen once accepted. If a decision is later superseded, the original ADR remains and a new one references it.

## Index

| # | Title | Status |
|---|---|---|
| [0001](0001-end-to-end-engineering-as-operating-standard.md) | End-to-end engineering as operating standard | Accepted |
| [0002](0002-bigquery-as-data-warehouse.md) | BigQuery as data warehouse | Accepted |
| [0003](0003-pipeline-order-eda-before-transform.md) | Pipeline order: EDA before transform | Accepted |
| [0004](0004-star-schema-with-conformed-dimensions.md) | Star schema with conformed dimensions | Accepted |
| [0005](0005-dual-grain-fact-model.md) | Dual-grain fact model (order + line) | Accepted |
| [0006](0006-rfm-segmentation-with-ntile.md) | RFM segmentation with `NTILE(5)` | Accepted |
| [0007](0007-two-tier-margin-calculation.md) | Two-tier margin calculation | Accepted |
| [0008](0008-synthetic-data-with-realistic-quality-issues.md) | Synthetic data with realistic quality issues | Accepted |
