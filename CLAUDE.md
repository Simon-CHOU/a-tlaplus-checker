# a-tlaplus-checker — Project Conventions & Programming Discipline

> TLA+ formal verification workspace for the S3-like object storage service (`a-s3-like-oss`).
> Target project: `/home/simon/vibe-workspace/haskell-dojo/a-s3-like-oss`

## Mode of Operation

This project uses **ultracode** (`/effort ultracode`). Every substantive task is executed via
multi-agent `Workflow` orchestration — parallel agents, adversarial verification,
multi-phase pipelines. Solo only for conversational/trivial turns.

### When to Use Workflows

- Any multi-step task (assess → fix → verify → commit)
- Any task requiring parallel exploration or verification
- Any task where independent dimensions can be checked simultaneously

### Workflow Phases Convention

Standard phase names for dynamic workflows:
1. `Assess` — audit current state, identify gaps
2. `Fix` — apply fixes via parallel agents with worktree isolation
3. `Verify` — re-run all checks (TLC, lint, tests)
4. `Commit` — update docs, stage, commit with descriptive message

### Agent Dispatch Conventions

- Labels: kebab-case describing the task (`audit-checker`, `fix-auth-bypass`, `reverify-all`)
- Isolation: use `isolation: 'worktree'` for file-mutating agents
- Agent types: `Explore` for discovery, default for implementation
- Pipeline is default for multi-stage work; `parallel()` only when genuinely need barrier

---

## TLA+ Conventions

### File Naming
- Specs: `PascalCase.tla` (e.g., `PolicyEngine.tla`)
- Configs: same `PascalCase.cfg`
- Traces: `SpecName_TTrace_<timestamp>.tla` + `.bin`

### Command
```bash
java -cp ../tla2tools.jar tlc2.TLC -config <name>.cfg <name>.tla
```

### Formatting
- Use `\*` line comments, **never** `(* ... *)` block comments — `(*)` inside a block
  comment closes it prematurely
- No space between `\` and `*` in comment delimiter (`\*` not `\ *`)
- Use `IF-THEN-ELSE` instead of `/\ ` for guarded lookups — TLA+ does NOT short-circuit
- Use `[x \in {} |-> expr]` for empty function initialization, never `{}` alone
- Use LET-IN single assignment for primed variables — never `x' = A /\ x' = B`
- Use `[x \in S |-> CASE ...]` for string-keyed function construction — TLC rejects
  `["key" |-> val]` record syntax
- Use small CONSTANT sets for PolicyRecord — TLC fails on SUBSET enumeration >1M elements
- Invariant naming: CamelCase (`DenyOverrides`, `NoOrphanObjects`)

### Modeling
- Step-bounded models preferred over explicit clock models (avoids state explosion)
- CONSTANT parameters defined in spec-level operators, not in `.cfg` files
  (TLC `.cfg` parser rejects `[k |-> v]` and `@@` merge syntax)
- Model results format: states generated, distinct states, depth, invariants verified

### .cfg File Template
```
SPECIFICATION Spec
CONSTANTS
  Buckets = {b1, b2}
  ObjectKeys = {k1, k2}
  MaxPolicies = 3
  MaxOps = 4
INVARIANTS
  InvariantOne
  InvariantTwo
```

---

## Documentation Conventions

### Spike Files (`docs/spike-YYYYMMDD-HHMMSS.log`)

For open-ended investigation, blocking problems, and gap analysis.

```markdown
# Spike: <Short Title>
**Timestamp:** YYYY-MM-DD HH:MM
**Scope:** <concise description>

---

## Findings

| # | Item | Severity | Detail |
|---|------|----------|--------|

## Recommended Action Order
| Step | Action | Impact |
|------|--------|--------|
```

### Report Files (`docs/report-YYYYMMDD-HHMMSS.log`)

For cumulative E2E UAT-style progress reports.

```markdown
# <Title> — YYYY-MM-DD HH:MM

## 1. Project Status
## 2. Code Line Count
## 3. Gaps from Goal
## 4. Session Pitfalls (cumulative N)
## 5. System Health
```

### Final Report (`docs/report-YYYYMMDD-final.log`)

Polished executive deliverable with:
1. Executive Summary
2. Verification Results (spec-by-spec)
3. Implementation Bugs Found
4. Contract Verification Matrix
5. Remaining Gaps
6. TLA+ Code Statistics
7. Session Pitfalls

### Verification Results (`specs/VERIFICATION_RESULTS.md`)

Canonical cumulative document with:
- Spec-by-spec results table with states, invariants, assertions
- Verification Summary (7-spec rollup)
- Gap Closure Status (Closed / Open tables)
- Implementation Bugs Discovered
- Implementation Contract Review
- Session Pitfalls (cumulative)

---

## Severity Taxonomy

| Severity | Criteria |
|----------|----------|
| CRITICAL | Security bypass, data loss, state corruption |
| HIGH | Correctness gap, schema dead code, missing enforcement |
| MEDIUM | Missing feature, alignment gap, deferred verification |
| LOW | Dead code, unmodeled edge case, minor issues |

---

## Git Conventions

### When to Commit
- After ALL verifications pass (TLC, lint, tests)
- After each logical chunk of work
- Baseline first, then iterate

### Commit Message Format
```
<type>: <descriptive summary>

<detailed bullet points if needed>
```

Types: `fix:`, `docs:`, `feat:`, `spec:`

### Pre-Commit Rule
Zero lint/compiler warnings. No `--no-verify`. No "I'll fix it later."

---

## TLA+ Pitfalls (Cumulative)

When hitting a TLA+ issue, document it here and in the session report:

1. **`(*)` in block comment** — use `\*` line comments instead
2. **Non-short-circuit `/\ `** — use IF-THEN-ELSE for guarded lookups
3. **`{}` not a function** — use `[x \in {} |-> e]` for empty functions
4. **Double primed-variable** — use LET-IN single assignment
5. **State explosion** — use step-bounded model, remove explicit clock/tick
6. **CFG function constants** — use spec operators, not cfg-level `[k|->v]`
7. **String-keyed records** — use `[x \in S |-> CASE ...]` instead of `["k"|->v]`
8. **SUBSET of large sets** — use small CONSTANT sets for PolicyRecord enumeration
9. **`\ *` vs `\*`** — no space between backslash and asterisk in comment delimiter

---

## Project Structure

```
a-tlaplus-checker/
  tla2tools.jar              # TLC model checker v2026.05.26
  .claude/settings.json      # { "ultracode": true }
  specs/
    *.tla                    # TLA+ specifications
    *.cfg                    # TLC configuration files
    VERIFICATION_RESULTS.md  # Canonical results document
    states/                  # TLC checkpoint directories (per run)
  docs/
    spike-*.log              # Investigatory spike reports
    report-*.log             # E2E UAT progress reports
```

## Target Project

```
/home/simon/vibe-workspace/haskell-dojo/a-s3-like-oss/
  src/S3OSS/
    Auth/Policy.hs, SigV4.hs
    Bucket/Handler.hs
    Object/Handler.hs, Storage.hs
    List/Handler.hs
    Multipart/Handler.hs, Manager.hs
    Server.hs, Store.hs, Types.hs, Config.hs, XML.hs
```

---

## Remaining Gaps (as of 2026-06-12)

| Gap | Severity | Status |
|-----|----------|--------|
| Presigned URLs | MEDIUM | Deferred (requires time-based model) |
| List pagination | LOW | Unmodeled (prefix/delimiter/maxKeys) |
| SigV4 crypto | LOW | Deferred to property-based testing |
| Dead test modules | LOW | 3 test files never imported in test/Spec.hs |
