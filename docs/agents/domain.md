# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

**Layout: single-context** — one `CONTEXT.md` and one `docs/adr/`, both at the repo root.

## Before exploring, read these

- **`CONTEXT.md`** at the repo root — the glossary and domain overview.
- **`docs/adr/`** — read the ADRs that touch the area you're about to work in.

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates them lazily when terms or decisions actually get resolved.

## File structure

```
/
├── CONTEXT.md
├── docs/adr/
│   ├── 0001-platform-baseline.md
│   ├── 0002-project-topology.md   ← superseded by 0018
│   └── …0018-app-target-and-mvvm.md
└── HisaabWise/
    ├── HisaabWise.xcodeproj
    ├── HisaabWise/               ← the app, by MVVM layer (ADR-0018)
    └── HisaabWiseTests/
```

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `CONTEXT.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal — either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (device-bound refresh token) — but worth reopening because…_

The workspace specs outrank both `CONTEXT.md` and the ADRs. Precedence is: project rules in `../CLAUDE.md` → `HisaabWise_Product_Spec.md` → `HisaabWise_Technical_Spec.md` → `HisaabwiseDesigns/` → these docs. An ADR that contradicts a resolved decision in the Product Spec is the ADR's problem.
