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

**WARNING**: None remaining — see Phase 5 Live Verification below; both runtime warnings from the initial sandbox pass were closed with real evidence, one of which uncovered and fixed an actual bug.
- No `actionlint` available to catch GitHub Actions-specific schema issues beyond generic YAML syntax — accepted, low-impact gap (workflows were validated live instead, a stronger signal than a linter).

**SUGGESTION**: Resolved — `.gitignore` added, stray `go-hadolint-poc` binary removed (both post-verify, pre-commit).

## Phase 5 — Live Post-Merge Verification (executed against the real repo)

All 5 tasks executed for real against `github.com/robbasualto/go-hadolint-poc` after this report's initial sandbox pass:

1. **5.1 PASS (with a bug found and fixed)** — Opened throwaway PR #1 with a planted generic API-key secret. First attempt: `gitleaks` job errored with "GITHUB_TOKEN is now required to scan pull requests" — it never reached the scan. Root cause: `gitleaks-action@v3` requires an explicit `GITHUB_TOKEN` env var for `pull_request` events (breaking change vs v2). Fixed in `ci.yml` (commit `5ecbb2c`). Re-ran: `gitleaks` correctly failed with "🛑 Leaks detected", blocking the PR. PR closed unmerged, branch deleted.
2. **5.2 PASS** — The original push to master (commit `cc4c97f`) ran all 5 jobs green; `gitleaks` reported "✅ No leaks detected"; the other 4 jobs were unaffected (no shared `needs:` edge).
3. **5.3 PASS** — Pushed real tag `v0.1.0`. `release` workflow run succeeded in 1m15s (all 6 gates + build + smoke test). `gh release view v0.1.0` confirms a published GitHub Release exists at `https://github.com/robbasualto/go-hadolint-poc/releases/tag/v0.1.0`.
4. **5.4 PASS** — Pushed throwaway tag `v0.0.0-test-fail` on a commit with a deliberate `gofmt` violation. `gofmt check` step failed; all downstream steps (golangci-lint, hadolint, docker build, smoke test, `Create GitHub Release`) were skipped per GitHub Actions' default fail-fast step sequencing; job conclusion `failure`; `gh release view v0.0.0-test-fail` returned "release not found". Tag deleted (local + remote) after confirmation.
5. **5.5 PASS** — Across all real runs (both `ci.yml` executions and the `v0.1.0` release run), no `docker push`, `ghcr`, `syft`, or `cosign` step exists or executed in either workflow.

All throwaway artifacts (PR #1, branch `test/gitleaks-detection`, branch `test/release-failure`, tag `v0.0.0-test-fail`) were deleted after verification; nothing test-related was merged to master. One real bug (missing `GITHUB_TOKEN` for PR-triggered gitleaks scans) and one earlier bug (invalid `config-path` input on `golangci-lint-action@v9.3.0`) were found and fixed during this verification pass, each as its own commit.

## Final Verdict

**PASS** — all MUST requirements from both spec deltas are satisfied by both static inspection and real, live execution against the actual GitHub repository: a genuine planted secret was detected and blocked (after fixing a real missing-token bug), a clean push passed cleanly, a real tag created a real GitHub Release, a tag with a broken gate created no Release, and zero registry calls occurred anywhere. No open items remain.
