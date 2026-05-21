# Triage labels

This repository uses **9 labels** total: 5 status (canonical mattpocock roles) + 4 type. Priority and version live in GitHub Projects v2 custom fields and Milestones — NOT labels.

## Status labels (5 canonical roles)

These are the five canonical roles defined by the mattpocock `/triage` skill. Every issue must have exactly one status label at any time. This repo uses **prefixed strings** (`status:` / `closed:`) to group labels visually in the GitHub UI — the canonical role still applies.

| Label in repo | Canonical role | Color | Meaning |
|---|---|---|---|
| `status:needs-triage` | `needs-triage` | `#fbca04` (yellow) | Fresh issue, hasn't been categorized yet. The default starting state. |
| `status:needs-info` | `needs-info` | `#d4c5f9` (light purple) | Triage is blocked on missing information from the reporter or stakeholder. |
| `ai-ready` | `ready-for-agent` | `#0e8a16` (green) | Ready for an agent to pick up and execute. Has clear acceptance criteria. |
| `human-required` | `ready-for-human` | `#1d76db` (blue) | Needs human review, code review, or manual testing. |
| `closed:wontfix` | `wontfix` | `#ffffff` (white) | Closed without action. Issue is invalid, out of scope, or superseded. |

## Type labels (4 categories)

These are additive: an issue can have zero or one type label. Use them to categorize the kind of work, not the urgency.

| Label | Color | Meaning |
|---|---|---|
| `type:bug` | `#d73a4a` (red) | Something works incorrectly. |
| `type:feature` | `#a2eeef` (cyan) | New capability. |
| `type:refactor` | `#fef2c0` (pale yellow) | Internal improvement, no behavior change. |
| `type:docs` | `#0075ca` (blue) | Documentation only. |

## What goes in custom fields, not labels

| Concern | Where it lives |
|---|---|
| Priority (P0, P1, P2) | GitHub Projects v2 custom field `Priority` (single-select: P0, P1, P2, P3) |
| Size estimate (S, M, L, XL) | GitHub Projects v2 custom field `Size` (single-select) |
| Version (v1.0.0, v1.0.1, v1.1) | GitHub Milestones |
| Current workflow position (Backlog, In Progress, Review, Done) | GitHub Projects v2 custom field `Status` |

## How `/mp-triage` uses this file

The skill reads this file at the start of each triage session and matches issues to one of the 5 canonical roles. If the user has customized label strings (e.g., `agent-ready` instead of `ready-for-agent`), the skill respects that — but the canonical role name is still what it reasons about internally.

If you want to customize the label strings, edit the table above. Keep the canonical role names in the right-hand column unchanged.

## Canonical role → repo label mapping (for skill consumption)

| Label in mattpocock/skills | Label in this repo | Meaning |
| --- | --- | --- |
| `needs-triage` | `status:needs-triage` | Maintainer needs to evaluate this issue |
| `needs-info` | `status:needs-info` | Waiting on reporter for more information |
| `ready-for-agent` | `ai-ready` | Fully specified, ready for an AFK agent |
| `ready-for-human` | `human-required` | Requires human implementation |
| `wontfix` | `closed:wontfix` | Will not be actioned |

When a skill mentions a canonical role (e.g., "apply the AFK-ready triage label"), use the corresponding string from this table. Edit the right-hand column if the vocabulary ever diverges.
