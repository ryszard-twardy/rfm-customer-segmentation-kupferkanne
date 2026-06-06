# AGENTS.md

Master agent configuration for `rfm-customer-segmentation-kupferkanne`. Read this file first when starting any session.

## Project

- **Name**: rfm-customer-segmentation-kupferkanne
- **Stack**: data (data | trading | generic)
- **Owner**: Ryszard Twardy (`r.twardy@proton.me`)
- **Status**: v1.0.2 shipped + tagged; next: 04_5 release (BI-facing customer dimension)
- **Primary objective**: RFM (Recency, Frequency, Monetary) customer segmentation for Kupferkanne e-commerce – BigQuery modeling + Power BI BI layer + Python pipelines.

## How this repo works

This repo follows the **workflow v3** convention. Key files and directories:

| Location | Purpose | Public? |
|---|---|---|
| `AGENTS.md` | This file. Master config. | ✅ |
| `CLAUDE.md` | 3-line stub → redirects here. | ✅ |
| `CONTEXT.md` | DDD ubiquitous language glossary. | ✅ |
| `docs/adr/` | Architectural Decision Records. | ✅ |
| `docs/agents/` | Per-repo mattpocock configuration. | ✅ |
| `.checkpoints/` | Session checkpoints (L0+L1+L2 living docs). | ❌ gitignored |
| `.personal/` | Recruiter QA, methodology lessons. | ❌ gitignored |
| `.scratch/` | WIP, debug sessions, raw inbox. | ❌ gitignored |
| `.specify/memory/constitution-data.md` | Stack-specific invariants. | ✅ |

## Agent skills

### Issue tracker

GitHub Issues – operate via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Canonical 5-role vocabulary + 4 type labels (Opcja D, workflow v3). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context – `CONTEXT.md` + `docs/adr/` at repo root. See `docs/agents/domain.md`.

### Configured skills

- `/mp-triage`, `/mp-to-issues`, `/mp-to-prd` – consume `docs/agents/issue-tracker.md` + `docs/agents/triage-labels.md`
- `/mp-grill-with-docs`, `/mp-improve-arch` – consume `CONTEXT.md` + `docs/adr/`
- `/mp-handoff` – conversation compaction
- `/rt-checkpoint-emit`, `/rt-repo-bootstrap` – Ryszard custom skills (see `.checkpoints/` and this file)

## Conventions

- **Typography**: en-dash `–` (never em-dash `U+2014`), ASCII quotes only, backticks for code/paths/identifiers.
- **Filesystem**: dot-prefix everywhere. `_checkpoints/` is legacy and must not appear.
- **Backups**: `$env:PROJECTS_ROOT\.backups\rfm-customer-segmentation-kupferkanne\` (outside repo, per-machine).
- **Cross-machine**: this repo syncs via git.

## Sessions

Each session ends with a CHECKPOINT in `.checkpoints/CHECKPOINT_kupferkanne_<date>_v<n>.md`. The format is L0 INDEX + L1 CORE + L2 DELTA + STORAGE + LOAD_NEXT_THREAD + FUTURE-AI + SELF-CHECK. See `/rt-checkpoint-emit` for the exact schema.

The latest CHECKPOINT is the source of truth for "where are we now". Read it before starting any new session.

## Open questions

Add `[?]` items here as they arise. Resolve them by either making a decision (and logging it in `.checkpoints/L2_DECISIONS.md`) or escalating to the user.

- [?] (none currently)
