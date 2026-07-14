# 0009 – Analytical Notebook with Quarto

**Status**: Accepted  
**Date**: 2026-07-14  

## Context

The pipeline's exploratory layer is a set of eight SQL EDA views – queryable, joinable, and reproducible without a runtime. What the views cannot carry is the reasoning. The exploration that shaped the transformation design – quintile choice, recency anchor, threshold bands – survives only as view definitions and code comments; the distributions themselves, the observations drawn from them, and the path from observation to decision are not readable anywhere without running the queries and reconstructing the argument. The BI report is not the place for that either: it is a consumption layer that presents outcomes, not analytical reasoning.

This split was anticipated when the pipeline order was decided ([ADR 0003](0003-pipeline-order-eda-before-transform.md) rejected moving EDA into a notebook *only*, on the grounds that notebooks complement but do not replace queryable views); this record formalises the complement.

## Decision

Add a Quarto notebook, `eda_kupferkanne.qmd`, as the narrative companion to the SQL EDA views. The notebook reads the EDA layer, renders the distributions and the reasoning built on them, and compiles to a self-contained static HTML report published with GitHub Pages from the same repository.

The sources of truth stay split by strength: the views hold the queryable, reproducible definitions; the notebook holds the narrative – what the distributions look like, what was concluded, and how those conclusions shaped the transformation design.

## Consequences

- Quarto becomes a build dependency. Rendering is a local step that produces static HTML; no runtime service is added, and the published artifact has no server-side dependency.
- The notebook requires warehouse access at render time; the rendered HTML does not. A reader gets the full narrative without credentials or infrastructure.
- On the free plan, GitHub Pages publishes only from a public repository, so publication is coupled to the repository visibility change already planned. The notebook can be authored and rendered before that change and published after it.
- The notebook becomes the canonical narrative home for EDA findings that currently live only in view definitions and code comments; prose duplicated elsewhere should point to it rather than restate it.
- Source, rendered report, and hosting all live in one ecosystem – the GitHub repository – with no second hosting account or deployment pipeline to maintain.

## Alternatives Considered

- **Jupyter notebook committed raw** – rejected. An `.ipynb` source embeds outputs and metadata in the file, making diffs noisy and review awkward. Quarto's `.qmd` is plain text: diffable, reviewable, with outputs produced at render time.
- **External hosting (e.g. Vercel)** – rejected. A second ecosystem and account for zero functional gain when the artifact is static HTML living in the same repository that GitHub Pages can serve.
- **Extend the SQL views only** – rejected on the grounds recorded in the pipeline-ordering decision: the views are the queryable layer, not a narrative one. More views add coverage, not reasoning.
- **Embed the exploration in the Power BI report** – rejected. The report is the consumption layer; it presents outcomes to a reader, not the analytical path behind design decisions. Wrong medium.
