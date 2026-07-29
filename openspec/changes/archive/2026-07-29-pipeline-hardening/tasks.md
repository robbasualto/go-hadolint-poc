# Tasks: Pipeline Hardening (secrets scanning + release automation)

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~65 (ci.yml +8, release.yml new +55, config.yaml ~2) |
| 400-line budget risk | Low |
| Chained PRs recommended | No |
| Suggested split | Single PR |
| Delivery strategy | ask-on-risk |
| Chain strategy | pending |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: pending
400-line budget risk: Low

### Suggested Work Units

| Unit | Goal | Likely PR | Focused test command | Runtime harness | Rollback boundary |
|------|------|-----------|----------------------|-----------------|-------------------|
| 1 | Ship gitleaks job + release.yml + config fix | PR 1 | `gh workflow view ci.yml` / `gh workflow view release.yml` (YAML validity) | Real: planted-secret PR + real `v0.1.0` tag push, verified via `gh release list` | Delete `gitleaks` job block, delete `release.yml`, revert config hunk — independently, no shared state |

## Phase 1: Version Resolution & Threat-Matrix Assertions (RED)

- [x] 1.1 Resolve current stable `gitleaks/gitleaks-action` tag via `gh api repos/gitleaks/gitleaks-action/releases/latest --jq .tag_name`; confirm it matches `v3.x.y` — never guess, never float `v3`.
- [x] 1.2 RED: Assert release workflow MUST do zero `git push`/registry push and MUST set `push: false` on the build step — confirm unmet before `release.yml` exists (Threat Matrix: Push state).
- [x] 1.3 RED: Assert the tag MUST reach `gh` only via `env: TAG: ${{ github.ref_name }}` used as `"$TAG"`, never `${{ }}` interpolated into a `run:` body (Threat Matrix: PR/release commands, script-injection boundary).
- [x] 1.4 RED: Assert all git operations in both workflows use only `actions/checkout`, no `git -C`/relative-path git commands (Threat Matrix: Git repository selection).

## Phase 2: CI Hardening (GREEN)

- [x] 2.1 Add `gitleaks` job to `.github/workflows/ci.yml`: no `needs:`, `actions/checkout@v4` with `fetch-depth: 0`, `gitleaks/gitleaks-action@<tag from 1.1>` (spec: Secrets Scanning Gate; Scenario "Clean history passes"; satisfies 1.4).
- [x] 2.2 Confirm the existing 4 jobs (`go-build-test`, `go-lint`, `hadolint`, `docker-build`) remain byte-identical, no new `needs:` edge added.

## Phase 3: Release Workflow (GREEN)

- [x] 3.1 Create `.github/workflows/release.yml`: `on: push: tags: ["v*"]`, single job `release`, `permissions: contents: write` (spec: Tag-Triggered Release Workflow).
- [x] 3.2 Inline-duplicate build/vet/test/gofmt/golangci-lint/hadolint steps from `ci.yml`, sequential, no `workflow_call` extraction (spec: Independent Gate Re-Verification).
- [x] 3.3 Add Docker build step mirroring `ci.yml`'s pair: `docker/build-push-action@v6`, `push: false`, tag `${{ github.ref_name }}` (satisfies 1.2).
- [x] 3.4 Add smoke-test step: `docker run --rm` stdout MUST equal exactly `Hello, world!`, gating release creation (spec: Image Build and Smoke Proof).
- [x] 3.5 Add final step `gh release create "$TAG" --generate-notes` with `env: TAG: ${{ github.ref_name }}` (spec: Conditional GitHub Release Creation; satisfies 1.3).
- [x] 3.6 Confirm no registry-push, SBOM (syft), or signing (cosign) step exists anywhere in `release.yml` (spec: No Registry Push; No SBOM or Image Signing).

## Phase 4: Config Correction

- [x] 4.1 Update `openspec/config.yaml` `context` block `Repo:` line: replace "no remote" with `remote https://github.com/robbasualto/go-hadolint-poc (public), default branch master`.

## Phase 5: Pipeline Verification

- [x] 5.1 Open a throwaway PR with a planted test credential; confirm `gitleaks` fails and blocks (spec: "A genuine secret is present"). **Live evidence**: PR #1 (closed, unmerged, branch deleted) with a planted generic API key — `gitleaks` job failed with "🛑 Leaks detected". Along the way found and fixed a real bug: `gitleaks-action@v3` requires an explicit `GITHUB_TOKEN` env var on `pull_request` events or it errors out before scanning at all (fixed in ci.yml, commit `5ecbb2c`).
- [x] 5.2 Confirm a clean PR passes `gitleaks` without affecting the other 4 jobs (spec: "Clean history passes"). **Live evidence**: initial push to master after apply (commit `cc4c97f`) ran all 5 jobs green, `gitleaks` reported "✅ No leaks detected".
- [x] 5.3 Push a passing-commit tag (e.g. `v0.1.0`); confirm `release.yml` triggers, all gates run, and a GitHub Release is created with auto-notes, verified via `gh release list`. **Live evidence**: tag `v0.1.0` pushed, `release` workflow run 30484877465 succeeded in 1m15s, `gh release view v0.1.0` confirms a published Release exists.
- [x] 5.4 Push a tag on a commit with an intentionally failing gate; confirm no GitHub Release is created (spec: "A gate fails"). **Live evidence**: throwaway tag `v0.0.0-test-fail` (deleted after test) on a commit with a deliberate `gofmt` violation — `gofmt check` step failed, all subsequent steps including `Create GitHub Release` were skipped, job conclusion `failure`, `gh release view v0.0.0-test-fail` returned "release not found".
- [x] 5.5 Confirm zero registry network calls during the passing release run (spec: "Workflow makes no registry calls"). **Live evidence**: confirmed across all real runs (v0.1.0 release, both ci.yml runs) — no `docker push`, `ghcr`, `syft`, or `cosign` step exists or ran anywhere in either workflow.
