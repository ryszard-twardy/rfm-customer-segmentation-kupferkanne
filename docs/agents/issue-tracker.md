# Issue tracker configuration

This repository uses **GitHub Issues** as the primary issue tracker.

- **Repository**: `ryszard-twardy/rfm-customer-segmentation-kupferkanne`
- **URL**: `https://github.com/ryszard-twardy/rfm-customer-segmentation-kupferkanne/issues`
- **Default visibility**: PRIVATE (until v1.2.0 PUBLIC flip)
- **Projects v2 ID**: `PVT_kwHODYeDCc4BYXw3` (board #1, linked to repo; consumed by `/mp-to-issues` for field assignment)

## Skills that consume this file

- `/mp-to-issues` – publishes new issues here
- `/mp-to-prd` – creates PRDs as long-form issues here
- `/mp-triage` – reads and re-labels existing issues here

## Drafts and exploratory issues

Issues that are not yet ready for the team tracker go to `.scratch/local-issues.md` (gitignored). Skills should NOT publish exploratory or half-formed tickets to GitHub directly.

When a draft is ready, the user runs `/mp-to-issues` explicitly with the draft as input to publish.

## Required fields per issue

Every published issue must have:

- Clear title (verb-first, action-oriented)
- Body with: context, expected behavior, current behavior, acceptance criteria
- One or more of the canonical triage labels (see `triage-labels.md`)
- An optional type label (see `triage-labels.md`)
- Optional milestone (see Milestones section below)

## Milestones

This repo uses GitHub Milestones for version tracking. Skills should suggest the right milestone based on context, but never assign automatically without user confirmation.

- `v1.0.0` – initial stable release (shipped)
- `v1.0.1` – model-hygiene batch: Best Practice Analyzer findings, format-string and SummarizeBy normalisation, plus the measures catalogue rewrite (shipped)
- `v1.0.2` – agent-configuration and documentation-hygiene release (shipped)
- `v1.1.0` – Power BI dashboard build-out and semantic-model consolidation: full seven-page report, PBIP / TMDL migration, and dimension consolidation onto `dim_Segment` and `dim_Customer` (shipped)
- `v1.2.0` – planned: Quarto analytical notebook and companion ADR, Customer Drillthrough detail page, and the issue-tracker PUBLIC flip

## Operating via the `gh` CLI

- Create issue: `gh issue create --title "..." --body "..."` (use HEREDOC for multi-line bodies)
- View issue: `gh issue view <number> --comments`
- List issues (JSON): `gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'`
- Comment: `gh issue comment <number> --body "..."`
- Apply/remove labels: `gh issue edit <number> --add-label "..." --remove-label "..."`
- Close: `gh issue close <number> --comment "..."`

`gh` infers the repo from `git remote -v` when run inside a clone.

## When a skill says "publish to the issue tracker"

Create a GitHub issue.

## When a skill says "fetch the relevant ticket"

`gh issue view <number> --comments`.
