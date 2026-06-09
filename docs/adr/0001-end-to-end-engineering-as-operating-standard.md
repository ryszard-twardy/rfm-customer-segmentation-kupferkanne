# 0001 – End-to-End Engineering as Operating Standard

**Status**: Accepted  
**Date**: 2026-05-11

## Context

Kupferkanne is a fictional Erlangen-based D2C e-commerce brand operating across nine European markets with 38 months of order data (~169K orders from ~15,000 customers). The business needs to answer three commercial questions: which customers to invest in (segmentation), which products and brands drive profitability, and how much revenue sits at churn risk.

A single analyst is responsible for the analytics platform end-to-end: data ingestion, warehouse modelling, BI consumption, documentation. The choice of build philosophy – full engineering pipeline vs. exploratory dashboards layered on quick SQL – affects every downstream decision: data sourcing, schema discipline, pipeline structure, testing depth.

## Decision

Adopt **end-to-end engineering discipline** as the operating standard. The platform covers the full data engineering cycle: data generation with documented quality issues, schema-enforced ingestion, idempotent SQL pipelines, exploratory data analysis preceding transformation, dimensional modelling, BI consumption with grain-strict measure naming, and architecture documentation via ADRs.

Scope stays narrow (one business problem, six dashboard pages, ~440K records) so each layer meets production quality.

## Consequences

- Companion data generator [synth-datagen](https://github.com/ryszard-twardy/synth-datagen) maintained as separately versioned engineering capability, supporting controlled regeneration without depending on real customer data.
- SQL is lint-clean (SQLFluff 4.1.0 with documented exception policy).
- Every strategic choice has a written ADR; tactical rules live in internal documentation.
- Platform is fully reproducible: `synth-datagen --scenario retail --seed <SEED>` plus pipeline re-run produces byte-identical state.
- Single point of accountability (one analyst) is balanced by full audit trail (ADRs + audit tables + lint enforcement).

## Alternatives Considered

- **Anonymised real customer data** – rejected on privacy grounds. Cleaning rules feel arbitrary when the data shape cannot be controlled.
- **Public dataset (Kaggle, UCI Online Retail II)** – rejected. Such datasets are pre-cleaned, eliminating the cleaning pipeline's purpose as a working processing step.
- **Quick exploratory dashboards without full pipeline** – rejected. Kupferkanne's question set requires reproducibility (audit trail, recovery from upstream changes, regenerable training data). A notebook-style approach loses these properties.
- **Multiple smaller analytical exercises** – rejected. One end-to-end platform demonstrates integration discipline that disconnected exercises cannot.

Note (2026-06-09): the report now has 7 pages (Customer Lifecycle Intelligence added at page 5). Canonical page list: methodology.md.
