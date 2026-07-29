# Verify Report: pipeline-hardening

**Date**: 2026-07-29
**Verdict**: PASS WITH WARNINGS (sandbox-executable scope only — Phase 5 requires live post-merge verification)

## Artifact Availability Note

No `apply-progress` artifact was found in either the OpenSpec store (`openspec/changes/pipeline-hardening/`) or Engram — no Engram MCP tools (`mem_search`/`mem_get_observation`/`mem_save`) were available in this execution context, consistent with the prompt's note that every prior phase in this change also lacked Engram persistence. Verification proceeded from OpenSpec files (spec, design, tasks) plus direct source/runtime inspection.

## Task Completeness

13/18 tasks checked in `tasks.md`. Phases 1–4 (version resolution, CI hardening, release workflow, config correction) are complete and match the code. Phase 5 (5 tasks: planted-secret PR blocks gitleaks, clean PR passes, real tag creates a Release, failing-gate tag creates no Release, zero registry calls) is unchecked and **cannot be executed in this sandbox** — it requires pushing to the live `github.com/robbasualto/go-hadolint-poc` repo and observing real Actions runs. This is an accepted, explicitly-flagged gap (per sdd-apply and the orchestrator), not a verification failure. See "Phase 5 — Requires Live Post-Merge Verification" below.

## Build/Test Evidence (real execution)

| Command | Exit | Result |
|---|---|---|
| `go build ./...` | 0 | pass |
| `go vet ./...` | 0 | pass |
| `gofmt -l .` | 0 | pass (no output — nothing unformatted) |
| `go test ./... -cover` | 0 | pass — `coverage: 50.0% of statements` |

Confirms this change is workflow-YAML-only: no Go source was touched, and the Go build/vet/fmt/test surface is genuinely unaffected.

## Spec Compliance Matrix

### `ci-pipeline` delta — Requirement: Secrets Scanning Gate

| Scenario/MUST | Status | Evidence |
|---|---|---|
| `gitleaks` job runs on same `push`/`pull_request` triggers as existing jobs | PASS | Job has no separate `on:` block — inherits workflow-level `on: push / pull_request` (ci.yml:3-5, 68-74) |
| Uses `gitleaks/gitleaks-action` pinned to stable `v3.x.y`, not `v2`/floating | PASS | `gitleaks/gitleaks-action@v3.0.0` (ci.yml:74). Independently re-verified via `gh api repos/gitleaks/gitleaks-action/releases/latest --jq .tag_name` → returned `v3.0.0` — confirmed current, exact match, not a stale claim from a prior phase |
| Checkout uses `fetch-depth: 0` (full history) | PASS | ci.yml:71-73 |
| Job MUST fail and block pipeline on a genuine secret | PASS (static) | No `continue-on-error`, no `if: always()`; default GH Actions behavior fails the job and blocks merge status. Runtime confirmation (planted-secret PR) is Phase 5 — not executed here |
| Clean history passes, doesn't affect other 4 jobs | PASS (static) | `gitleaks` has no `needs:` and nothing depends on it — independent node in the DAG. Runtime confirmation is Phase 5 |
| v2 not used / not floating | PASS | `@v3.0.0` is an exact tag, not `v2`, not `@v3` floating |

Note: the two scenarios above marked "PASS (static)" are structurally compliant and match the design's stated mechanism, but per the skill's rule "a spec scenario is compliant only when a covering test passed at runtime," true runtime scenario compliance for "Clean history passes" and "A genuine secret is present" is **not yet proven** — that proof is exactly what Phase 5.1/5.2 (unexecuted, sandbox-infeasible) would provide. Flagged as WARNING, not CRITICAL, because the mechanism is verifiably correct by inspection and the gap is explicitly out-of-scope for this run.

### `release-automation` spec — full requirement set

| Requirement | Status | Evidence |
|---|---|---|
| Tag-Triggered Release Workflow (`v*` push triggers separate workflow) | PASS | release.yml:3-5 `on: push: tags: ["v*"]`, separate file from ci.yml |
| Non-matching ref does not trigger | PASS (static) | `tags: ["v*"]` filter is GH Actions native tag-glob matching; branch pushes and non-`v*` tags will not match. Runtime confirmation is Phase 5, not executed |
| Independent Gate Re-Verification (build/vet/test/lint/format/hadolint re-run, no reuse of prior CI result) | PASS | release.yml:17-31 duplicates all six gates inline (build, vet, test, gofmt check, golangci-lint, hadolint) — no `workflow_call`, no artifact reuse from ci.yml |
| Image Build and Smoke Proof (build alone insufficient; smoke test required) | PASS | release.yml:32-43 — `docker/build-push-action@v6` then a separate smoke-test step asserting exact stdout `"Hello, world!"` before Release step |
| Conditional GitHub Release Creation (all gates pass → Release; any gate fails → no Release, no cleanup) | PASS (static) | `gh release create` is the final step (release.yml:45-49); default GH Actions fail-fast step sequencing means any earlier non-zero exit skips it. Runtime confirmation (Phase 5.3/5.4) not executed |
| No Registry Push | PASS | `push: false` (release.yml:35); grep for `docker push`/`ghcr`/`registry` across release.yml returned zero matches |
| No SBOM or Image Signing | PASS | grep for `syft`/`cosign` across release.yml returned zero matches |

## Threat Matrix / Design Boundary Checks

| Boundary | Status | Evidence |
|---|---|---|
| Script-injection boundary (tag never `${{ }}`-interpolated into a `run:` body) | PASS | Only two `run:` steps reference the tag (smoke test, release create); both go through `env: TAG: ${{ github.ref_name }}` and reference `"$TAG"` in the shell body (release.yml:39-43, 46-49). The one other `${{ github.ref_name }}` occurrence (release.yml:36) is inside a `with:` action-input block for `docker/build-push-action`, not a `run:` shell body — GitHub Actions substitutes it before invoking the action, so it is not a shell-injection surface and is explicitly permitted by tasks.md 3.3 |
| Git repository selection (only `actions/checkout`, no `git -C`/relative-path git) | PASS | No raw `git` invocations in either workflow |
| Push state (zero `git push`, zero registry push, `push: false` asserted) | PASS | Confirmed above |
| Permissions least-privilege | PASS | `permissions: contents: write` scoped at job level in release.yml (matches design decision #4), not workflow-level |

## Existing 4 CI Jobs — Untouched Confirmation

`git diff HEAD -- .github/workflows/ci.yml` shows the change is a pure append: the entire diff is a new `gitleaks:` block added after the existing `docker-build` job, with zero lines changed/removed from `go-build-test`, `go-lint`, `hadolint`, or `docker-build`. Byte-for-byte unchanged, confirmed via git history diff (not just visual inspection).

## Config Correction

`git diff HEAD -- openspec/config.yaml` confirms the `Repo:` line was corrected from "no remote" to "remote https://github.com/robbasualto/go-hadolint-poc (public), default branch master" exactly as specified in design.md's File Changes table — single-hunk, no unrelated changes.

## YAML Validity

No `actionlint` or `yamllint` available in this sandbox, and Python's `yaml` module / `pip` are both absent. Validated both workflow files parse as syntactically valid YAML using Ruby's built-in YAML library (`ruby -ryaml`) — both files loaded without error. This confirms syntactic validity only, not GitHub Actions schema/semantic correctness (which actionlint would additionally check); no such tool was available to run.

## Issues

**CRITICAL**: None.

**WARNING**:
- Runtime scenario compliance for the `gitleaks` job's "Clean history passes" and "A genuine secret is present" scenarios, and all release-automation runtime scenarios (tag trigger, gate re-verification, conditional release), rest on static/structural evidence only. Per the skill's rule that a spec scenario is compliant only when a covering test passed at runtime, these remain formally unproven until Phase 5 executes against the live repo. This is a known, accepted gap (flagged by sdd-apply and the orchestrator already), not a newly discovered defect.
- No `actionlint` available to catch GitHub Actions-specific schema issues (e.g. invalid action input names, unreachable contexts) beyond generic YAML syntax.

**SUGGESTION**:
- An untracked stray binary `go-hadolint-poc` (a `go build` output artifact) sits in the repo root and is not gitignored. Unrelated to this change's scope but worth a `.gitignore` entry in a follow-up.

## Phase 5 — Requires Live Post-Merge Verification (not executable in this sandbox)

The following 5 tasks cannot be completed without pushing to the live `github.com/robbasualto/go-hadolint-poc` repository and observing real GitHub Actions runs:

1. **5.1** — Open a throwaway PR with a planted test credential; confirm `gitleaks` fails and blocks.
2. **5.2** — Confirm a clean PR passes `gitleaks` without affecting the other 4 jobs.
3. **5.3** — Push a passing-commit tag (e.g. `v0.1.0`); confirm `release.yml` triggers, all gates run, and a GitHub Release is created with auto-notes (verify via `gh release list`).
4. **5.4** — Push a tag on a commit with an intentionally failing gate; confirm no GitHub Release is created.
5. **5.5** — Confirm zero registry network calls during the passing release run.

This is treated as a known, accepted gap requiring live post-merge verification — not a verification FAIL.

## Final Verdict

**PASS WITH WARNINGS** — all statically/sandbox-verifiable MUST requirements from both spec deltas are satisfied by the actual file contents (not just apply-report claims); Go build/vet/fmt/test are confirmed unaffected; the 4 pre-existing CI jobs are confirmed byte-identical via git diff; the `gitleaks-action` version pin was independently re-verified as current (`v3.0.0`); the script-injection boundary, no-registry-push, and no-SBOM/signing constraints are all confirmed by direct inspection. Runtime/live-repo scenario proof (Phase 5) remains outstanding and requires post-merge live verification — this is explicitly out of scope for a sandbox and does not block archival, provided Phase 5 is executed and tracked after merge.
