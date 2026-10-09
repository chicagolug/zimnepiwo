# zimnepiwo Skills Router

## About

This directory contains discoverable Agent Skills for the zimnepiwo bootc image
template. Each skill lives in a lowercase directory with a required `SKILL.md`
file whose frontmatter tells compatible agents when to load it.

## Skill Index

| Skill | What it covers |
|---|---|
| [`router`](router/SKILL.md) | The task routing table: which skill covers what, and the standard sequence. Load when unsure. |
| [`overview`](overview/SKILL.md) | Repository architecture and file layout. Start here for orientation. |
| [`onboarding`](onboarding/SKILL.md) | Bootstrap a new fork: rename, enable Actions, first green build, raptor section, branch protection. |
| [`templates`](templates/SKILL.md) | The 7 rename locations, image identity ARGs, signing verification, AGENTS.md update rules. |
| [`packages`](packages/SKILL.md) | Decision tree: where to add packages (dnf5, Brew, Flatpak). |
| [`custom`](custom/SKILL.md) | Runtime layer: Brewfiles, Flatpaks, ujust, and validation. |
| [`build`](build/SKILL.md) | Containerfile, Justfile, build scripts, image pinning, advanced topics. |
| [`ci`](ci/SKILL.md) | GitHub Actions, Renovate, composite actions, workflow pins. |
| [`maintain`](maintain/SKILL.md) | Ongoing work: Renovate PRs, README raptor updates, local test loops. |
| [`troubleshooting`](troubleshooting/SKILL.md) | Symptom → cause → fix tables for build, CI, and runtime issues. |
| [`pr-checklist`](pr-checklist/SKILL.md) | Pre-commit and per-change-type validation checklists. |
| [`examples`](examples/SKILL.md) | Runnable example scripts and the `.example` → `.sh` activation pattern. |
| [`skill-improvement`](skill-improvement/SKILL.md) | Capture durable, zimnepiwo-specific operational learning. |

Looking for "I need to… → which skill?" — that table lives in
[`router`](router/SKILL.md), its single canonical home.

## How to Extend Skills

When adding a new skill:

1. **Create a lowercase directory** under `.agents/skills/`
2. **Add `SKILL.md`** with `name` and `description` frontmatter; `name` must match the directory
3. **Describe when to use the skill** precisely so agents can select it automatically
4. **Include the standard sections**: When to Use, When NOT to Use, Core Process, Common Rationalizations, Red Flags, Verification
5. **Add the skill to this README** and to the routing table in `router/SKILL.md`
6. **Keep `SKILL.md` focused** — split deep sub-topics into sibling `.md` files in the same directory and link them from `SKILL.md` (relative links, e.g. `[AGENT-BRIEF.md](AGENT-BRIEF.md)`)

## References

- [Adding agent skills for GitHub Copilot](https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/customize-cloud-agent/add-skills)
- [Agent Skills specification](https://agentskills.io/specification)
- [AGENTS.md](../../AGENTS.md) — high-level copilot instructions and mandatory gates
