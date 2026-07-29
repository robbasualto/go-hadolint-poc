# Proposal: Robust CI Pipeline

## Intent

The `go-test` CI job never runs `go test` — only `go build` and `go vet`. The repo declares `strict_tdd: true` yet has zero `*_test.go` files, no linter, no formatter check, no image scanning. CI gives a false green signal. Make the pipeline honest and proportionate to a no-deployment POC.

## Scope

### In Scope
- Fix `go-test` job to run `go test ./... -cover`.
- Add `golangci-lint` CI job with a **pinned** version plus a `.golangci.yml` ruleset (user-requested).
- Add a `gofmt -l` check that fails on unformatted files.
- Extract pure `func greeting() string` from `main.go`; add table-driven `main_test.go` (repo's first test).
- Add report-only (non-blocking) Trivy scan of the built Docker image.
- Update `openspec/config.yaml`: `testing.quality.linter`, `testing.quality.formatter`, and other now-stale flags.

### Out of Scope
Considered and deliberately deferred — no deployment target justifies them yet:
- SBOM generation (syft); multi-arch buildx; image signing (cosign).
- Semantic-version tagging / release automation; secrets scanning (gitleaks).
- GitHub branch-protection automation (repo setting, needs admin API — outside this repo).
- Hard coverage-threshold gating (no baseline exists to gate against).

## Capabilities

### New Capabilities
- `ci-pipeline`: required CI gates — build, vet, test with coverage, lint, format, Dockerfile lint, image build/smoke, report-only image scan.
- `app-greeting`: pure, testable greeting value separated from stdout side effects.

### Modified Capabilities
- None (`openspec/specs/` is empty).

## Approach

Exploration Approach 2. Fix the misnamed job first, then layer quality gates as separate CI jobs so failures stay attributable. Pin every tool version, matching the Dockerfile convention. Trivy stays `exit-code: 0` until a triaged baseline exists. TDD order: failing test → extraction → refactor.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `.github/workflows/ci.yml` | Modified | Real `go test`, gofmt check, lint + Trivy jobs |
| `.golangci.yml` | New | Pinned linter ruleset |
| `main.go` | Modified | Extract `greeting()` |
| `main_test.go` | New | First test |
| `openspec/config.yaml` | Modified | Sync stale quality flags |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Enabling tests/lint turns CI red immediately | High | Fix findings in-change; keep `.golangci.yml` minimal |
| Linter ruleset drift | Med | Pin version + explicit config |
| Trivy noise blocks merges | Med | Report-only, non-blocking |
| Extraction changes runtime output | Low | Test asserts exact string; smoke test unchanged |

**Runtime dependencies: none added.** golangci-lint and Trivy are CI-only tooling; `go.mod`/`go.sum` stay stdlib-only.

## Rollback Plan

Every deliverable is additive and independently revertible. `git revert` the change commit (or drop the added `ci.yml` job blocks) to restore prior CI; delete `.golangci.yml` and `main_test.go`; inline `greeting()` back into `main()`. No data, no deployment, no dependency to unwind.

## Dependencies

- GitHub Actions marketplace: `golangci/golangci-lint-action`, `aquasecurity/trivy-action` (pinned).

## Success Criteria

- [ ] CI fails when a Go test fails (provably: test job invokes `go test ./... -cover`).
- [ ] CI fails on unformatted code and on `.golangci.yml` violations.
- [ ] `main_test.go` exists and passes; `strict_tdd: true` is no longer contradicted.
- [ ] Trivy scan results visible in CI logs without blocking merges.
- [ ] `openspec/config.yaml` quality flags match reality.
