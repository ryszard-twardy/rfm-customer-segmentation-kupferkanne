# 0008 – Synthetic Data with Realistic Quality Issues

**Status**: Accepted  
**Date**: 2026-05-11

## Context

The platform needs to exercise a complete data engineering pipeline: schema enforcement, raw audit, cleaning, validation, transformation. None of this work has substance if the source data is already clean.

Public datasets (Kaggle, UCI, government open data) are typically pre-cleaned because they've been processed by the publisher. They are well-suited for ML/modelling workloads but leave a cleaning pipeline with no real work to do – the SQL has nothing to process.

Using real anonymised data introduces privacy and licensing concerns and removes control over the data shape.

## Decision

Generate the dataset with **[synth-datagen](https://github.com/ryszard-twardy/synth-datagen)**, a CLI tool maintained as a companion engineering capability specifically to support this approach. The generator seeds the output with intentional, documented quality issues:

- **Duplicate orders** – same `OrderID` reissued; deduplication uses deterministic ARG_MAX on a precedence field.
- **Cents-format inconsistency** – some shards store amounts as cents (`1500`), others as euros (`15.00`); cleaning normalises to euros.
- **Orphan keys** – small fraction of `OrderID`s in `items` reference no row in `orders`; cleaning quarantines via INNER JOIN.
- **Type drift** – `OrderDate` arrives as `STRING` in some shards, `DATE` in others; standardisation views cast.
- **Header-row contamination** – occasional shards have the header row repeated mid-file; audit detects, cleaning filters.
- **Missing values** – sparse nulls in optional columns; cleaning either imputes or flags.

These issues match patterns observed in real-world retail data warehouses and give the cleaning pipeline (step 01_0) genuine work to do.

## Consequences

- The cleaning pipeline addresses real data quality issues; audit tables show non-empty findings; post-clean validation confirms the issues are resolved.
- The dataset is fully regenerable: `synth-datagen --scenario retail --seed <SEED>` reproduces the exact same 80 CSV files. Pipeline runs are reproducible from a single seed value.
- synth-datagen is maintained as a separately versioned engineering capability (CLI tool, Python 3.12 with `uv`, audit-grade architecture) supporting controlled regeneration across multiple analytics initiatives.
- Data licensing is a non-issue (the author owns the generator and the output).
- 80 CSVs (~22 MB total) ship in the repository for direct consumption; the generator is linked for full reproducibility.

## Alternatives Considered

- **Public retail dataset (e.g., Online Retail II)** – rejected: pre-cleaned, eliminating the cleaning pipeline's purpose as a working processing step.
- **Anonymised real data** – rejected: privacy concerns, no control over the issue mix.
- **Hand-corrupted clean data** – rejected: less defensible than a documented generator. The generator is auditable and re-runnable.

Note (2026-10-02): the cents rule as first shipped caught only amounts above 1,000, so 69 lines in 67 orders stored as cents passed as euros. Since commit 18d6330, cleaning also reads a line amount as cents when it is at least 10 times its list value: amounts are net of a discount of at most 0.55, so a euro line sits at or below its list value and a cents line at least 45 times it. Duplicate line rows now resolve on an MD5 of the raw row instead of a random UUID, so every run keeps the same row. In ORD-2023-001914 / PROD-040, stored twice with equal values, one copy with spaces around the order key, the hash now keeps the clean copy where the last run before the fix kept the spaced one; the kept copy follows the hash, not a preference for clean copies, and the output values are the same either way.
