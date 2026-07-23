# Architecture

## Overview

Kupferkanne is a portfolio-grade retail analytics demonstration showing how a single-author analyst can deliver a complete data warehouse plus BI solution. It analyses 39 months of synthetic order data for a fictional Erlangen-based D2C e-commerce brand operating in nine European markets, identifies customer segments via RFM scoring, and surfaces findings through a seven-page Power BI dashboard.

## System diagram

```
+------------------+     +------------------+     +------------------+
|  synth-datagen   |---->|     BigQuery     |---->|     Power BI     |
|  (Python CLI)    |     |  data warehouse  |     |   Import mode    |
|                  |     |    9-step SQL    |     |   PBIP / TMDL    |
+------------------+     +------------------+     +------------------+
  80 CSV shards           33 objects created        7-page report
  ~460K raw records       11 tables + 22 views      109 DAX measures
```

_Twenty-five of those objects are BI-facing (11 tables + 14 `v_*` views); the remaining 8 `eda_*` views back the exploratory notebook._

## Tech stack

| Layer | Tool | Purpose |
|---|---|---|
| Data generation | [synth-datagen](https://github.com/ryszard-twardy/synth-datagen) | Python CLI producing realistic data with intentional quality issues |
| Data warehouse | Google BigQuery | Serverless cloud DW, GoogleSQL dialect |
| Transformation | 9-step SQL pipeline | Idempotent (`CREATE OR REPLACE`), lint-clean |
| Linting | SQLFluff | Custom rule policy |
| BI | Power BI (PBIP / TMDL) | Import mode, dual-grain semantic layer, model as code |
| Theme | Custom JSON | Segoe UI, navy primary on light grey background |
| DAX formatting | [daxformatter.com](https://www.daxformatter.com/) | SQLBI short-line conventions |

## Pipeline flow

The SQL layer follows the standard data engineering progression – **audit → clean → explore → transform → mart** – implemented across nine idempotent scripts. Exploratory analysis runs **before** RFM transformation, so that segmentation thresholds are informed by observed distribution shape rather than guessed assumptions. See [ADR 0003](adr/0003-pipeline-order-eda-before-transform.md) for the rationale.

The data model uses a Kimball-style star schema with two conformed dimensions and a **dual-grain** fact layer: order-grain `sales_curated` for revenue and segmentation, line-grain `v_items_for_bi` for product-level detail. This separation prevents aggregation errors that arise from joining mixed grains. See [ADR 0005](adr/0005-dual-grain-fact-model.md).

## Documentation map

- [data_model.md](data_model.md) – star schema, ERD, table specifications
- [methodology.md](methodology.md) – RFM approach, segmentation, margin calculation
- [measures.md](measures.md) – DAX measure catalogue
- [glossary.md](glossary.md) – domain terminology
- [adr/](adr/) – fourteen architecture decision records
