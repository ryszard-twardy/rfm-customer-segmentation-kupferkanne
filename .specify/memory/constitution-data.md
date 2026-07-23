# Constitution: rfm-customer-segmentation-kupferkanne (data stack)

Invariant rules for this project. These do not change session-to-session. If a rule needs to change, it requires a recorded decision in the project decision ledger AND a corresponding ADR in `docs/adr/`.

## Stack

- **Primary database / warehouse**: BigQuery
- **Modeling layer**: BigQuery views with `_curated`, `_staged`, `_raw` naming (no dbt)
- **BI tool**: Power BI, PBIP / TMDL format (migrated from `.pbix` in v1.1.0)
- **Pipeline / scripting**: Python 3.12 (3.13 not adopted for stability) with `uv` for env management
- **SQL linter**: `sqlfluff` with `.sqlfluff` config at repo root

## Invariants

### Data integrity

- **Grain Reconciliation must equal zero.** Always-on validation measure. If it's not zero, the model is broken – stop and fix before any other work.
- **No silent type coercions.** All BigQuery `CAST` operations are explicit. No implicit conversion via comparisons.
- **Foreign keys are documented in `docs/data_model.md`.** Skills must consult this file before suggesting JOIN modifications.

### Modeling rules

- **One fact table per grain.** Order-grain, line-grain, customer-grain – separate fact tables, not denormalized.
- **Dimensions follow `dim_<name>_std` convention.** `_std` suffix indicates standardized dimension (deduplicated, surrogate-keyed).
- **Aggregation for the star schema belongs in DAX measures, not in SQL views.** Where a visual needs its own grain, the pre-aggregated view is imported standalone, outside the star (this rule caused the v0.x → v1.0 model refactor).

### Power BI rules

- **PBIP / TMDL is the current working AND production format** (migrated from `.pbix` in v1.1.0). The model is versioned as text-based TMDL; the legacy `.pbix` report is retired.
- **DAX measures live in the model, NOT in calculated columns.** Calculated columns are an anti-pattern for this stack.
- **Format strings are explicit per measure.** Currency: `"€"#,##0.00;-"€"#,##0.00`. Percent: `0.00%`. Date: `dd-mmm-yyyy`.
- **Every measure has a `docs/measures.md` entry.** Sync these in the same session as any measure change (no batched documentation drift).

### Python rules

- **`uv` for env management, NOT pip-tools, poetry, or conda.** One canonical tool per stack.
- **Type hints required for any public function.** Checked in review, not by an automated gate.
- **Pipeline SQL lives in `sql/`, never inline in Python.** The parity harness is the one exception: its fixed reference queries interpolate table identifiers only.

### Repository rules

- **BPA findings get triaged within the session that introduces them.** Don't accumulate BPA debt.
- **ADRs are written BEFORE flipping to public visibility.** A PUBLIC repo without ADRs is incomplete.
- **`docs/measures.md` is the contract between SQL/model layer and BI layer.** Keep it accurate or skills will hallucinate measure definitions.

## When to amend this file

- Add a decision in the project decision ledger first.
- Write an ADR in `docs/adr/`.
- Update this file with a brief change note at the bottom.
- Reference the ADR in the change note where one applies.

## Change log

- 2026-05-21 – Initial constitution for `rfm-customer-segmentation-kupferkanne` (data stack).
- 2026-07-23 – Cross-references repointed to public documentation, the SQL-in-Python and pre-aggregation rules restated to match the shipped model, and an unenforced pre-commit claim removed.
