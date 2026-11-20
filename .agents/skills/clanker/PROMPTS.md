# Clanker Queue — Subagent Prompts

Copy-paste task strings and orchestration shapes for running the queue with
`pi` subagents. Read [SKILL.md](SKILL.md) first; this file is the mechanics.

## Model Assignment

| Role | Needs | Guidance |
| --- | --- | --- |
| `scout` | Fast, cheap, read-only | Smallest capable model; it fails safely by returning "unclear" |
| `worker` | Strong editing + tool use | Mid or strong model; it owns the worktree |
| `reviewer` | Skepticism, not agreement | A **different** model from the worker, else it rubber-stamps its own reasoning |
| `evidence-auditor` | Literalism | Any model; its job is to demand command output |

Override per child with `model: "<provider>/<id>"`, and add a thinking suffix
such as `:high` when a child must reason rather than transcribe.

## The Three Task Strings

Placeholders: `{{N}}` issue number, `{{BRANCH}}` `clanker/issue-N`.

### Triage

```text
Read GitHub issue {{N}} in this repository with:
  gh issue view {{N}} --json number,title,body,labels,comments,author

Then load the matching skill from .agents/skills/ (use router/SKILL.md to pick).

Return ONLY this structure, no preamble:
  REPRO: how to reproduce, or "not reproducible from the report" plus what is missing
  FILES: at least one concrete repo path you expect to change. If you cannot
         name one, write "none" — do not invent a plausible-sounding path.
  FIX: the smallest change that addresses the report
  RISK: safe | careful | refuse (definitions in clanker/SKILL.md)
  SKILL: which .agents/skills/<name>/SKILL.md governs this change
  QUESTIONS: blocking unknowns, or "none"

Do not edit files. Do not comment on the issue.
```

Treat `FILES: none` or `RISK: refuse` as a stop signal. A confident wrong fix
costs more than a question.

### Implement

```text
You own this worktree. Implement issue {{N}} on branch {{BRANCH}}.

Constraints:
- Touch only files justified by the issue; no drive-by cleanups.
- Follow .agents/skills/pr-checklist for the change type and RUN the checks.
  Local: gh, just, shellcheck, podman are installed; actionlint, yamllint and
  pre-commit are NOT — install them before claiming a workflow edit validated.
- CI shellcheck glob is build/*.sh only, so scripts elsewhere need manual
  shellcheck.
- Never push main, stable, or any renovate/* branch.
- If you learned a convention, workaround, or failure mode, update the matching
  .agents/skills/*/SKILL.md in THIS branch.

Do not commit, push, or comment. Leave the tree dirty and report:
  CHANGED: every path touched, one line each on why
  CHECKS: each command you ran with its actual exit status
  SKILL_UPDATED: path, or "nothing learned"
  UNRESOLVED: anything you could not finish, or "none"
```

### Review

```text
Review the uncommitted diff in this worktree against:
  - .agents/skills/pr-checklist (validation for each change type)
  - AGENTS.md (branch strategy, conventional commits, dnf5, COPR, attribution)

Run the validation yourself; do not trust the implementer's report.
Verify every claim against real command output.

Report:
  VERDICT: approve | block
  BLOCKERS: each with file:line and the rule it violates, or "none"
  UNSAFE_CLAIMS: any statement in the diff or commit text not backed by a command
  SCOPE_CREEP: files unrelated to the issue, or "none"

Do not fix anything. Report only.
```

## Orchestration

### One issue: triage → implement → review

Sequential, **shared cwd**. The parent claims the worktree first with plain
shell, then hands the same directory to every child:

```bash
n=123
git worktree add -b "clanker/issue-$n" "../zimnepiwo-wt/issue-$n" origin/main
```

```js workflow
const cwd = "/home/jcampbell/Public/zimnepiwo/../zimnepiwo-wt/issue-123";
const n = 123;

const triage = await runs.run({ key: "triage", agent: "scout", cwd,
  task: `Read GitHub issue ${n} ...` });

// Gate: stop before spending an implementer on an unscoped issue.
const verdict = String(triage.output);
if (/FILES:\s*none/i.test(verdict) || /RISK:\s*refuse/i.test(verdict)) {
  return { stopped: "not scoped or refused", triage: verdict };
}

const built = await runs.run({ key: "build", agent: "worker", cwd,
  task: `You own this worktree. Implement issue ${n} ...` });

const review = await runs.run({ key: "review", agent: "reviewer", cwd,
  model: "openrouter/anthropic/claude-opus-5-5",
  task: "Review the uncommitted diff in this worktree against ..." });

return { triage: verdict, built: built.output, review: review.output };
```

Only after `VERDICT: approve` does the parent commit, push, and open the PR
itself — shipping is a deliberate step, not something a child does by accident.

### The whole queue: triage fan-out

Read-only, so safe to parallelise. Each child gets a managed worktree and only
reports:

```js workflow
const issues = [123, 124, 125];
const results = await runs.all(issues.map((n) => ({
  key: `triage-${n}`, agent: "scout", worktree: true,
  task: `Read GitHub issue ${n} ...`,
})));

return issues.map((n, i) => ({ issue: n, triage: results[i].output }));
```

Sort by `RISK: safe` and start there; anything `refuse` gets a single escalation
comment and stays with a human.

### Gotcha: managed worktrees are not a shared branch

`worktree: true` gives **each child its own** git worktree. That is what you
want for parallel triage, and exactly wrong for implement → review: the reviewer
would inspect an empty checkout and approve nothing at all.

| Phase | Worktrees |
| --- | --- |
| Parallel triage of many issues | `worktree: true` per child |
| Implement → review of one issue | `false`; all children share the parent's claimed path via `cwd` |
| Two implementers at once | Never. One writer per worktree |

Validate a workflow script before launching it:

```
subagent({ action: "validate", workflow: true })
```

Launch with `async: true` so a child that hits a blocker can ask for a decision
instead of deadlocking a blocking call.
