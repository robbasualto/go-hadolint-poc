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

## Phase 5: Pipeline Verification (live, executed against the real GitHub repo)

- [x] 5.1 Opened throwaway PR #1 with a planted test credential (`api_token = "gk7f..."`). First attempt (Stripe-shaped key) was blocked by GitHub's own push protection before even reaching CI — confirmed a second, independent defense layer. Second attempt (generic key) reached CI: `gitleaks` failed with "🛑 Leaks detected", correctly blocking the PR. **Found and fixed a real bug in the process**: gitleaks-action v3 requires an explicit `GITHUB_TOKEN` env var for `pull_request` events or it errors out before scanning at all (was failing for the wrong reason until fixed in commit 5ecbb2c). PR #1 closed without merging, branch deleted.
- [x] 5.2 Confirmed via the `robust-pipeline`-era and this change's own push-triggered runs: `gitleaks` passes clean, other 4 jobs unaffected (byte-identical, `needs:` graph unchanged).
- [x] 5.3 Pushed real tag `v0.1.0`: `release.yml` triggered, all gates ran, image built, smoke test passed, GitHub Release created with auto-generated notes. Verified via `gh release view v0.1.0`.
- [x] 5.4 Pushed throwaway tag `v0.0.0-test-fail` on a commit with an intentional `gofmt` violation: `gofmt check` step failed, all subsequent steps (including `Create GitHub Release`) were skipped per GitHub Actions' default step-sequencing, job conclusion `failure`, confirmed via `gh release view v0.0.0-test-fail` → "release not found". Tag deleted (local + remote) after confirmation, throwaway branch deleted, never merged to master.
- [x] 5.5 Confirmed across all live runs (push, PR, and both tag pushes): zero `docker push`, zero registry hostnames, zero `syft`/`cosign` invocations anywhere in logs or workflow files.

**Bugs found and fixed during live verification** (both shipped to master):
- `config-path` is not a valid input for `golangci-lint-action@v9.3.0` (commit 4030130) — was silently ignored with a warning on every run; golangci-lint already auto-discovers `.golangci.yml`, so behavior was unaffected, just the dead input was removed.
- `gitleaks/gitleaks-action@v3.0.0` requires `GITHUB_TOKEN` passed explicitly via `env:` to scan `pull_request` events, or it errors before scanning (commit 5ecbb2c) — without this fix, PR-triggered gitleaks runs would fail for the wrong reason and never actually check for secrets.

**Known minor gap, not fixed** (out of scope, noted for awareness): gitleaks-action couldn't post a PR comment on the detected leak ("Resource not accessible by integration") because the default `GITHUB_TOKEN` for `pull_request`-triggered workflows is read-only in this repo. The failing check itself still blocks the PR correctly; only the convenience PR-comment annotation is missing. Would need `permissions: pull-requests: write` on the `gitleaks` job to fix, not requested as part of this change.
