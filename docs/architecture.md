# Architecture

## Overview

Kupferkanne is a portfolio-grade retail analytics demonstration showing how a single-author analyst can deliver a complete data warehouse plus BI solution. It analyses 39 months of synthetic order data for a fictional Erlangen-based D2C e-commerce brand operating in nine European markets, identifies customer segments via RFM scoring, and surfaces findings through a seven-page Power BI dashboard.

## System diagram

```
┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐
│  synth-datagen   │───▶│    BigQuery      │───▶│   Power BI       │
│  (Python CLI)    │    │  data warehouse  │    │   Desktop        │
│                  │    │  + 9-step SQL    │    │   (Import mode)  │
└──────────────────┘    └──────────────────┘    └──────────────────┘
   80 CSV files            25 BQ objects           7-page dashboard
   ~460K records           (11 tables + 14 views)  7 pages, 104 DAX
```

_Object counts reflect the live warehouse. The eight EDA views defined in `sql/02_eda` are pending a rewrite against the restructured staging schema._

## Tech stack

| Layer | Tool | Purpose |
|---|---|---|
| Data generation | [synth-datagen](https://github.com/ryszard-twardy/synth-datagen) | Python CLI producing realistic data with intentional quality issues |
| Data warehouse | Google BigQuery | Serverless cloud DW, GoogleSQL dialect |
| Transformation | 9-step SQL pipeline | Idempotent (`CREATE OR REPLACE`), lint-clean |
| Linting | SQLFluff | Custom rule policy |
| BI | Power BI Desktop | Import mode, dual-grain semantic layer |
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
