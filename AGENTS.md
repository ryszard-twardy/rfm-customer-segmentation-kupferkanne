# AGENTS.md

Master agent configuration for `rfm-customer-segmentation-kupferkanne`. Read this file first when starting any session.

## Project

- **Name**: rfm-customer-segmentation-kupferkanne
- **Stack**: data
- **Owner**: Ryszard Twardy (`r.twardy@proton.me`)
- **Status**: v1.1.0 tagged; Customer Drillthrough page and Quarto analytical notebook ahead (see `CHANGELOG.md`).
- **Primary objective**: RFM (Recency, Frequency, Monetary) customer segmentation for Kupferkanne e-commerce – BigQuery modeling + Power BI BI layer + Python pipelines.

## How this repo works

This repo follows the **workflow v3** convention. Key files and directories:

| Location | Purpose | Public? |
|---|---|---|
| `AGENTS.md` | This file. Master config. | ✅ |
| `CLAUDE.md` | 3-line stub → redirects here. | ✅ |
| `docs/adr/` | Architectural Decision Records. | ✅ |
| `docs/agents/` | Per-repo mattpocock configuration. | ✅ |
| `.specify/memory/constitution-data.md` | Stack-specific invariants. | ✅ |

## Agent skills

### Issue tracker

GitHub Issues – operate via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Canonical 5-role vocabulary + 4 type labels (workflow v3). See `docs/agents/triage-labels.md`.

### Domain docs

Architectural decisions live in `docs/adr/`.

### Configured skills

- `/mp-triage`, `/mp-to-issues`, `/mp-to-prd` – consume `docs/agents/issue-tracker.md` + `docs/agents/triage-labels.md`
- `/mp-handoff` – conversation compaction

## Conventions

- **Typography**: en-dash `–` (never em-dash `U+2014`), ASCII quotes only, backticks for code/paths/identifiers.
- **Filesystem**: dot-prefix everywhere; underscore-prefixed directory names are legacy and must not appear.
- **Backups**: `$env:PROJECTS_ROOT\.backups\rfm-customer-segmentation-kupferkanne\` (outside repo, per-machine).
- **Cross-machine**: this repo syncs via git.
