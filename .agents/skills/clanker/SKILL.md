---
name: clanker
description: >-
  Issue and PR work queue for zimnepiwo: the eligibility gate, worktree
  isolation, subagent fan-out (scout → worker → reviewer), shipping a PR, and
  repairing failing Renovate PRs. Use when picking up a 3-clanker-queue issue,
  automating issue resolution with gh, or fixing a red automated PR.
---

# Clanker Queue

Turning a filed issue into a reviewable PR with an agent, without violating the
branch, signing, or comment rules that this repository enforces.

## When to Use

- An issue carries `3-clanker-queue` and you are about to work it
- Automating resolution of GitHub issues with `gh` + subagents
- A Renovate or promotion PR is red and you need to decide who fixes it
- Triaging a new issue into (or out of) the queue

## When NOT to Use

- The issue is not labelled `3-clanker-queue` — no label, no work
- You need package placement decisions — `packages`
- You need to know *where* a change goes — `build`, `custom`, `ci`
- You are deciding whether a change is safe to merge — that is a human

## The Two Gates

Consent and scope are **separate**, and both are machine-readable:

| Gate | Label | Set by | Meaning |
| --- | --- | --- | --- |
| Consent | `agent-opt-in` | `.github/workflows/clanker-optin.yml` | Reporter ticked "Opt in to a clanker working on my issue" |
| Scope | `3-clanker-queue` | **A human**, after triage | This is scoped enough to implement |

An issue is workable only when **both** are present and the issue is open.
`1-triage` is the default landing label from every issue form; it means nobody
has looked yet.

```bash
gh issue list --label 3-clanker-queue --state open --limit 50 \
  --json number,title,labels,url
```

Before writing any code, confirm eligibility for one issue:

```bash
gh issue view 123 --json state,title,labels,body \
  --jq '{state, title, labels: [.labels[].name]}'
```

Stop and hand back to a human if any of these is true:

- `3-clanker-queue` is missing (scope not granted)
- `agent-opt-in` is missing (consent not granted)
- `release/blocked` is present (release gate owns it)
- The issue asks for a change in the Refuse column below
- The request is ambiguous enough that two engineers would build different things

## Risk Classes

| Class | Examples | Agent may |
| --- | --- | --- |
| Safe | Docs, README, `.agents/skills/*`, Brewfile, flatpak list, ujust shortcuts, build-script bug fix | Ship a PR |
| Careful | `Containerfile` `FROM` pins, `.github/workflows/*`, `.github/renovate.json`, `Justfile` | Ship a PR, but the reviewer must re-read the whole diff against `pr-checklist` |
| Refuse | Release gate, cosign/keyless signing, promotion branch, `main`/`stable` pushes, secrets, branch strategy in `AGENTS.md`, any write to `ublue-os/*` or `projectbluefin/*` | Stop, comment, escalate |

Upstream repositories are **read-only**. Research them with `gh api`; never open
a PR or push a branch there.

## Core Process

### 1. Claim and isolate

One issue, one writer, one worktree. Never run two agents in one checkout.

```bash
n=123
git worktree add -b "clanker/issue-$n" "../zimnepiwo-wt/issue-$n" origin/main
cd "../zimnepiwo-wt/issue-$n"
```

Branch names are always `clanker/issue-N`. Never push `main` or `stable`.

### 2. Triage (delegate to `scout`)

Cheap model, read-only. It reads the issue, loads the matching domain skill, and
returns: reproduction, affected files, candidate fix, risk class, open questions.

If the scout cannot name at least one concrete file, the issue is not ready —
comment once, remove `3-clanker-queue`, and stop. A confident wrong fix costs more
than a question.

### 3. Implement (delegate to `worker`)

The worker owns the worktree for the whole edit. It must:

- Touch only files justified by the issue
- Run the validation for its change type (see `pr-checklist`)
- Update the matching `.agents/skills/*/SKILL.md` in the **same** PR if it
  discovered a convention, workaround, or failure mode

Local tooling reality check — `actionlint`, `yamllint`, and `pre-commit` are
**not** installed on this machine, while `gh`, `just`, `shellcheck`, and
`podman` are. CI's shellcheck glob is `build/*.sh` only, so a script created
anywhere else is never checked by CI. Install before claiming a workflow change
is validated:

```bash
brew install actionlint yamllint pre-commit
```

### 4. Verify (delegate to `reviewer` + `evidence-auditor`)

Independent verification, not a restatement of the worker's summary. The
reviewer re-reads the diff against `pr-checklist` and `AGENTS.md`; the auditor
checks every claim ("tests pass", "flatpak ID exists", "digest matches tag")
against real command output. A claim without a command is not evidence.

### 5. Ship

```bash
git add -A
git commit -F - <<'MSG'
fix(ci): correct shellcheck glob in pr-validation

The factory action only receives build/*.sh, so scripts added under
custom/ were never linted.

Assisted-by: <model> via pi
MSG
git push -u origin "clanker/issue-$n"
gh pr create --base main --head "clanker/issue-$n" \
  --title "fix(ci): correct shellcheck glob" \
  --body "Closes #123"
```

Commits are conventional commits with the `Assisted-by:` footer. The PR body
uses `Closes #N` so the issue closes on merge.

### 6. Comment policy

**One comment per PR event.** After opening, post at most a single combined
comment. Fold later observations into it with `gh pr comment --edit-last`
instead of posting again. Never restate CI status, approval counts, or merge
queue state — GitHub already shows those. If the only news is "checks pass",
say nothing.

## Renovate Lane

Renovate owns its branches: `recreateWhen: always` and
`rebaseWhen: behind-base-branch` mean a hand-pushed commit is discarded on the
next run. **Never commit to `renovate/*`.**

| Symptom | Action |
| --- | --- |
| Stale branch, rebase needed | Check the Dependency Dashboard box, or comment `@renovate rebase` |
| Failing check caused by the bump | Diagnose, then fix the root cause in a separate `clanker/` branch |
| Bump needs a config change to land | Edit `.github/renovate.json` in a `clanker/` branch; **never widen automerge beyond `digest`/`pin`/`pinDigest`** |
| Any pull toward `stable` or the promotion PR | Refuse — promotion is a human merge after testing `:stable-testing` |

## Common Rationalizations

| Rationalization | Reality |
| --- | --- |
| "It's a trivial fix, the label doesn't matter." | The label *is* the human's decision to pay for the work. Skipping it makes the queue meaningless and drafts PRs nobody asked for. |
| "The checkbox said they want agent help, so I can start." | Consent without scope means the issue is still unscoped. Both gates, always. |
| "I'll push the fix straight onto the renovate branch." | `recreateWhen: always` deletes it. Your work vanishes and the dashboard reopens the PR unchanged. |
| "Two subagents in one checkout will be faster." | Interleaved writes and `git add -A` produce cross-contaminated commits. One writer per worktree. |
| "I'll update the skill in a follow-up PR." | The learning is gone by then. Same PR, or do not claim the work is done. |
| "The reviewer said it looks fine." | A reviewer that did not run anything is a second opinion, not evidence. |
| "CI is green, so it's validated." | CI's shellcheck glob is `build/*.sh`. Workflow, YAML, and Brewfile changes need the local checks. |

## Red Flags

- A commit touching more than the issue's scope, or several unrelated fixes
- Any `git push` targeting `main`, `stable`, or a `renovate/*` branch
- Work starting on an issue with no `3-clanker-queue`
- `cosign.key`, `.github/workflows/promote-main-to-stable.yml`, or the release
  gate appearing in a diff
- A second comment on the same PR, or a comment that only reports check status
- No `.agents/skills/` change in a PR that discovered something new
- `Assisted-by:` footer missing

## Verification

- [ ] Issue had `3-clanker-queue` **and** `agent-opt-in` before work started
- [ ] Branch is `clanker/issue-N`, cut from `origin/main`, pushed to `origin`
- [ ] Diff is limited to the issue's scope
- [ ] Local validation for the change type ran and passed (`pr-checklist`)
- [ ] Skill update included if anything was learned
- [ ] Conventional commit + `Assisted-by:` footer
- [ ] PR body has `Closes #N`
- [ ] At most one comment posted

Exact subagent task strings live in [PROMPTS.md](PROMPTS.md).
