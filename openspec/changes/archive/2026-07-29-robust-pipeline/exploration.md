# Exploration: robust-pipeline

## Current State

- `main.go`: single `func main()` calling `fmt.Println("Hello, world!")`. No pure/testable function extracted yet.
- `go.mod`: module `go-hadolint-poc`, Go 1.26.5, zero dependencies.
- `Dockerfile`: multi-stage (`golang:1.26.5-bookworm` builder -> `gcr.io/distroless/base-debian12:nonroot`), pinned tags, `COPY` not `ADD`, exec-form `ENTRYPOINT`, non-root user. Already hadolint-clean.
- `.github/workflows/ci.yml` — 3 jobs:
  - `go-test`: **misnamed — only runs `go build ./...` and `go vet ./...`. Never invokes `go test`.** This is the most significant existing correctness gap, independent of the golangci-lint request.
  - `hadolint`: lints the Dockerfile via `hadolint/hadolint-action@v3.1.0`.
  - `docker-build`: needs both prior jobs; builds the image and runs it once as a smoke test.
  - No caching, no lint job, no `gofmt` check, no image scanning, no SBOM, no multi-arch, no tagging strategy.
- `openspec/config.yaml` already documents the gaps: `strict_tdd: true`, zero test files, `quality.linter: false`, `quality.formatter: false`, `verify.coverage_threshold: 0`.

## Affected Areas

- `.github/workflows/ci.yml` — fix `go-test` job to actually run tests; add a lint job; candidate spot for an image scan job.
- `main.go` — needs a testable extraction point (currently none) for Strict TDD to apply meaningfully.
- New file: `main_test.go` — first test in the repo.
- New file: `.golangci.yml` — pin golangci-lint's ruleset instead of relying on its floating defaults.
- `openspec/config.yaml` — update `quality.linter`, `quality.formatter`, `verify.coverage_threshold` once this change lands.

## Approaches Considered

1. **Minimal (golangci-lint only)** — smallest diff, but leaves `go-test` not testing anything and leaves the Strict-TDD/zero-tests contradiction unresolved. Effort: low.
2. **Proportionate POC-robust pipeline (recommended)** — fix `go-test` to run `go test ./... -cover`; add golangci-lint job with pinned version + `.golangci.yml`; add `gofmt -l` check; add first test via a pure-function extraction from `main.go`; add a Trivy scan of the built image (report-only initially); update `openspec/config.yaml` flags to match reality. Effort: medium.
3. **Full production-grade pipeline** — everything in (2) plus SBOM (syft), multi-arch builds (buildx), image signing (cosign), semantic-version tagging/release automation, secrets scanning (gitleaks), branch-protection automation. No production deployment target exists yet to justify this; branch protection is also a GitHub repo setting, not a CI artifact. Effort: high.

## Recommendation

Approach 2. It fixes the CI job that never actually runs tests, delivers the user-confirmed golangci-lint scope, and adds a lightweight image scan proportionate to a Dockerfile-focused POC, without over-engineering release/signing/multi-arch machinery this repo doesn't need yet. Approach 3 items should be named as explicitly **out of scope for now** in the proposal, not silently dropped.

## Scope Boundaries

- **Proportionate**: running tests in CI, linting, formatting, a lightweight vulnerability scan of the Docker image, keeping version pins consistent with existing Dockerfile conventions.
- **Overkill for now (defer, name explicitly)**: multi-arch builds, image signing, SBOM generation, semantic release automation, hard coverage-threshold gating before any real coverage exists.

## Strict TDD / First-Test Risk

- `strict_tdd: true` is set, but zero `*_test.go` files exist and `main.go` predates this contract.
- `main()` as written has no return value and no injected writer — testing it would mean shelling out and grepping stdout, disproportionate ceremony for a hello-world.
- Recommended scaffolding (RED-GREEN-REFACTOR): extract `func greeting() string { return "Hello, world!" }`, have `main()` call `fmt.Println(greeting())`, add `main_test.go` with a table-driven test asserting `greeting() == "Hello, world!"`. Write the failing test first, then the extraction, then refactor if needed.
- `verify.coverage_threshold` should stay non-gating immediately after this change — a single trivial test doesn't justify a hard coverage gate yet.

## Risks

- CI's `go-test` job doesn't run `go test` today — a real, previously unnoticed gap; call it out explicitly in the proposal.
- Strict TDD is active with zero existing tests — any task plan touching `main.go` must retrofit the first test via the extraction pattern above, or the change itself would violate the project's own TDD contract.
- golangci-lint needs a pinned version + `.golangci.yml` to avoid ruleset drift as its defaults change over time.
- Scope creep: SBOM/multi-arch/signing/release-automation are natural "robust pipeline" asks but have no current deployment target — name them as explicitly deferred so the user consciously accepts or expands scope later.

## Ready for Proposal

Yes — recommend `sdd-propose` scope this as Approach 2, with Approach 3 items listed as explicitly deferred/out-of-scope for user confirmation.
