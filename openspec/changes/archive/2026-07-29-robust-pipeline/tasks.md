# Tasks: Robust CI Pipeline

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~170-190 (main.go ~10, main_test.go ~20, .golangci.yml ~18, ci.yml ~110-130 rewrite, config.yaml ~10) |
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
| 1 | Ship all 5 file changes as one deliverable (well under 400-line budget) | PR 1 | `go test ./... -cover` | `docker build . -t go-hadolint-poc:ci && docker run --rm go-hadolint-poc:ci` | `git revert` the commit; each ci.yml job block is independently removable |

## Phase 1: App Greeting Extraction (TDD)

- [x] 1.1 RED: create `main_test.go` with table-driven `TestGreeting` calling `greeting()` (expect compile failure — `greeting()` doesn't exist yet)
- [x] 1.2 GREEN: extract `func greeting() string { return "Hello, world!" }` in `main.go`; `main()` becomes `fmt.Println(greeting())`
- [x] 1.3 Verify `greeting()` stays declared in `package main` with no new package/directory; run `go test ./... -cover` and confirm pass

## Phase 2: Open-Question Verification (must resolve before pinning)

- [x] 2.1 Verify current stable release pairing: **RESOLVED — the design's guess of `@v8` was wrong.** Live check of the golangci-lint-action GitHub API/README on 2026-07-29 shows current stable is `golangci-lint-action@v9.3.0`, paired with golangci-lint `v2.12.2` (latest v2.x) and config schema `version: "2"` — matches `.golangci.yml`. Verified further by installing golangci-lint v2.12.2 locally and running it against the checked-in config: `0 issues`.
- [x] 2.2 Confirm `docker/build-push-action@v6` (no `setup-buildx-action`) loads `go-hadolint-poc:ci` into the local Docker daemon store, since both the smoke test and the new Trivy step depend on it — **RESOLVED.** Docker's own build-drivers doc confirms the default `docker` driver (used automatically when no `setup-buildx-action` builder is created) auto-loads into the local image store, unlike `docker-container`. Confirmed empirically: local `docker build -t go-hadolint-poc:ci .` + `docker run --rm go-hadolint-poc:ci` both succeeded without any explicit `--load`/`load: true`.

## Phase 3: Lint and Format Configuration

- [x] 3.1 Create `.golangci.yml`: schema `version: "2"`, `linters.default: standard` (errcheck, govet, ineffassign, staticcheck, unused)
- [x] 3.2 Run `gofmt -l .` locally against `main.go` and `main_test.go`; confirm empty output before wiring the CI gate

## Phase 4: CI Pipeline Restructure (`.github/workflows/ci.yml`)

- [x] 4.1 Rename `go-test` job to `go-build-test`; add `go test ./... -cover` step after existing build/vet steps
- [x] 4.2 Add `go-lint` job: `gofmt -l .` step wrapped to exit non-zero when it lists files (per design snippet)
- [x] 4.3 Add pinned `golangci-lint-action` step to `go-lint` job, `config-path: .golangci.yml`, version confirmed in task 2.1 (`@v9.3.0`, golangci-lint `v2.12.2`)
- [x] 4.4 Add Trivy scan step inside `docker-build`, after the smoke test: `format: table`, `exit-code: 0`, `continue-on-error: true` (pinned `aquasecurity/trivy-action@v0.36.0`, current stable per live release check)
- [x] 4.5 Update `docker-build` job's `needs:` to `[go-build-test, go-lint, hadolint]`

## Phase 5: Config Sync and Full Verification

- [x] 5.1 Update `openspec/config.yaml`: set `quality.linter: true`, `quality.formatter: true`, update `layers.unit` note, remove stale "zero test files" claim from `context`
- [x] 5.2 Run full local check: `go build ./... && go vet ./... && go test ./... -cover && gofmt -l .`, then `docker build . -t go-hadolint-poc:ci && docker run --rm go-hadolint-poc:ci` — all passed (see Work Unit Evidence in apply-progress)
