# a-tlaplus-checker v0.1.0 GA

**Release Date:** 2026-06-12

## Overview

Formal TLA+ verification workspace for `a-s3-like-oss` — an S3-compatible local-first object storage service. This release provides machine-checked correctness proofs for all core subsystems.

## Verification Results

| # | Specification | Invariants | ASSUME | Result |
|---|---------------|-----------|--------|--------|
| 1 | PolicyEngine.tla | 6 | — | PASS |
| 2 | MultipartUpload.tla | 4 | — | PASS |
| 3 | ContentAddressableStorage.tla | 7 | — | PASS |
| 4 | BucketOps.tla | 2 | — | PASS |
| 5 | SigV4Replay.tla | 3 | — | PASS |
| 6 | AuthEnforcement.tla | 3 | 5 | PASS |
| 7 | EndpointCoverage.tla | — | 11 | PASS |

**Total: 7 specifications, 25 invariants + 16 ASSUME assertions = 41 total, 0 violations**

## Bugs Found & Fixed

- **CRITICAL: PutObject auth bypass** — PUT /{bucket}/{key} inline code bypassed IAM policy evaluation. Fixed by routing through `handlePutObject` with `evaluate()` call.
- **MEDIUM: handleCopyObject orphaned** — Server-side CopyObject defined but never wired into Server.hs route table. Fixed by adding `x-amz-copy-source` header dispatch.
- **LOW: Dead test modules** — 3 test modules compiled but never executed. Fixed by importing them in `test/Spec.hs`.

## Specifications Covered

1. **IAM Policy Engine** (258K states) — Deny-overrides semantics, wildcard matching, monotonicity, removal safety
2. **Multipart Upload State Machine** (727 states) — Upload lifecycle with GC, state consistency
3. **Content-Addressable Storage** (45 states) — SHA-256 addressing, ref-counting, no dangling keys
4. **Bucket Operations** (141 states) — Bucket create/delete with orphan-object prevention
5. **SigV4 Replay Protection** (65 states) — Timestamp validation, signature uniqueness
6. **Auth Enforcement Matrix** (258K states) — 14-endpoint handler-to-Action mapping, resource ARN correctness
7. **Endpoint Coverage** (static) — Route wiring contract, zero orphaned handlers, zero unauthorized routes

## Toolchain

- TLC2 Model Checker v2026.05.26 (`tla2tools.jar`)
- Java CLASSPATH invocation: `java -cp tla2tools.jar tlc2.TLC -config <name>.cfg <name>.tla`

## Known Gaps (Deferred)

- Presigned URLs — requires time-based model (MEDIUM)
- List pagination — prefix/delimiter/maxKeys unmodeled (LOW)
- SigV4 cryptographic verification — deferred to property-based testing (LOW)
