# Domain documentation layout

## Single-context repo (default)

This repo has one domain. Documentation layout:

```
/
├── CONTEXT.md           ← ubiquitous language glossary (root)
├── docs/
│   └── adr/             ← architectural decision records
│       ├── 0001-<topic>.md
│       └── 0002-<topic>.md
└── src/                 ← code
```

Skills that consume this layout:
- `/mp-grill-with-docs` reads `CONTEXT.md` and `docs/adr/*.md`. It updates `CONTEXT.md` inline when terms are resolved during grilling. It offers to create new ADRs when a decision is hard-to-reverse, impacts multiple parts of the codebase, and represents a real tradeoff.
- `/mp-improve-arch` reads `CONTEXT.md` and `docs/adr/*.md` to inform refactor proposals.
- `/mp-domain-model` (alpha — not currently adopted) would extend this layout with explicit DDD building blocks.

## Multi-context repo

If this repo has multiple bounded contexts (e.g., `ordering` and `billing` as separate subsystems), add `CONTEXT-MAP.md` at the root and per-context `CONTEXT.md` files:

```
/
├── CONTEXT-MAP.md       ← system-wide relationships
├── docs/adr/            ← system-wide decisions
└── src/
    ├── ordering/
    │   ├── CONTEXT.md
    │   └── docs/adr/    ← ordering-specific decisions
    └── billing/
        ├── CONTEXT.md
        └── docs/adr/
```

Most repos don't need this. Only switch to multi-context when you have genuine bounded contexts with different ubiquitous languages.

## Lazy creation

`CONTEXT.md` and `docs/adr/*.md` are created lazily during planning sessions (typically via `/mp-grill-with-docs`). They start mostly empty. Don't pre-populate them with speculative content — wait for real decisions to crystallize.

## ADR criteria

Only create an ADR when ALL THREE are true:
1. **Hard to reverse** — the cost of changing your mind later is meaningful.
2. **Architectural impact** — it shapes how multiple parts of the codebase interact.
3. **Real tradeoff** — there were genuine alternatives, not just "the obvious choice".

Bug fixes, naming choices, and routine implementation decisions do NOT get ADRs. They go in commit messages, code comments, or `CONTEXT.md` if they involve domain vocabulary.

## Before exploring, skills read these

- **`CONTEXT.md`** at the repo root, or
- **`CONTEXT-MAP.md`** at the repo root if it exists (it points at per-context `CONTEXT.md` files)
- **`docs/adr/`** — ADRs that touch the area being worked on

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The producer skill (`/mp-grill-with-docs`) creates them lazily when terms or decisions actually get resolved.

## Use the glossary's vocabulary

When skill output names a domain concept (issue title, refactor proposal, hypothesis, test name), use the term as defined in `CONTEXT.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept isn't in the glossary yet, that's a signal — either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/mp-grill-with-docs`).

## Flag ADR conflicts

If skill output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (segment dimensions snowflake) — but worth reopening because…_
