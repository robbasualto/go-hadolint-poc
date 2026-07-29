# Design: Robust CI Pipeline

## Technical Approach

Keep the single `package main` (no new packages — the `app-greeting` spec forbids one). Extract `greeting()` in place, add the repo's first `main_test.go`, restructure `.github/workflows/ci.yml` into four attributable jobs, all tool versions pinned per the Dockerfile convention.

**Hard constraint found in `Dockerfile`:** it uses `COPY main.go ./` and `go build -o server main.go` — an explicit file list, not `COPY . .`. Any new non-test `.go` file silently breaks the image build. Production code MUST stay in `main.go` until the Dockerfile is generalised (out of scope).

## Architecture Decisions

| # | Decision | Alternatives rejected | Rationale |
|---|---|---|---|
| 1 | `greeting()` returns the literal directly; `main()` = `fmt.Println(greeting())` | Package-level `const greetingText` | Spec forbids the greeting literal living outside the function; a const re-introduces it |
| 2 | Purity ("no stdout") verified structurally, not by capturing `os.Stdout` | `os.Pipe` redirect in the test | Stdout capture in `package main` is fragile and yields no signal a code read doesn't; the binary's real stdout is asserted in the smoke test instead |
| 3 | Rename `go-test` → `go-build-test`; runs build + vet + test | Keep `go-test`, just add the test step | The job still builds and vets; an accurate name prevents this exact drift recurring. `go test` recompiles anyway, so one job avoids a redundant compile |
| 4 | `gofmt -l` lives in the `go-lint` job, wrapped to force a non-zero exit | Its own job; `golangci-lint` formatters | `gofmt -l` exits **0** even when it lists files, so a bare `run:` is a fake gate. Same toolchain as lint ⇒ one runner. Enabling golangci-lint formatters would double-report the same violation |
| 5 | `.golangci.yml` uses schema `version: "2"` with `linters.default: standard` (errcheck, govet, ineffassign, staticcheck, unused) | `default: all`; curated opinionated set | Confirmed default: near-default. A 7-line program cannot justify a ruleset that needs triage; `all` guarantees day-one red CI (proposal risk row 1) |
| 6 | Trivy is a **step inside `docker-build`**, after the smoke test | Separate job `needs: docker-build` | A separate job needs the image back: `docker save`→artifact→`docker load` (~100 MB round-trip) or a full rebuild. Attributability is the only gain, worth ~nothing for a step that can never fail the build |
| 7 | Trivy visibility = `format: table` to the job log, `exit-code: 0`, plus `continue-on-error: true` | SARIF → `upload-sarif` (Security tab) | SARIF needs `security-events: write` **and** Advanced Security on private repos; this repo has **no remote at all**, so the path is unverifiable today. `continue-on-error` also absorbs Trivy DB-download flakes, which `exit-code: 0` alone does not |
| 8 | Smoke test asserts exact stdout | Bare `docker run --rm` (status only) | Covers `app-greeting` "Program output matches function output"; the alternative is a Go E2E layer `config.yaml` marks absent |

## Data Flow

```
push / pull_request
        │
        ├─ go-build-test ── build ─→ vet ─→ test -cover
        ├─ go-lint ──────── gofmt -l gate ─→ golangci-lint (pinned)
        └─ hadolint ─────── Dockerfile
                 │
                 └─ all three green ─→ docker-build
                                        │
                                        ├─ build image  (tag go-hadolint-poc:ci)
                                        ├─ smoke test   (assert stdout)  ← may fail job
                                        └─ trivy scan   (report-only)    ← never fails job
```

Trivy reads the tag from the local daemon image store in the same job — no handoff.

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `main.go` | Modify | Extract `greeting() string`; `main()` prints it |
| `main_test.go` | Create | Table-driven `TestGreeting`; repo's first test |
| `.golangci.yml` | Create | Schema v2, `linters.default: standard` |
| `.github/workflows/ci.yml` | Modify | 4 jobs per graph above |
| `openspec/config.yaml` | Modify | `quality.linter: true`, `formatter: true`, `layers.unit` note, remove "zero test files" claim from `context` |

## Interfaces / Contracts

```go
// main.go
func greeting() string { return "Hello, world!" }
func main()            { fmt.Println(greeting()) }
```

```go
// main_test.go — table-driven, one row today, extensible
tests := []struct{ name, want string }{
    {"canonical greeting", "Hello, world!"},
}
```

```yaml
# ci.yml — gofmt gate; `gofmt -l` alone exits 0 on violations
- name: gofmt check
  run: |
    out=$(gofmt -l .)
    [ -z "$out" ] || { echo "::error::unformatted: $out"; exit 1; }
```

## Testing Strategy

| Layer | What to Test | Approach |
|-------|-------------|----------|
| Unit | `greeting()` returns exact string | `go test ./... -cover`, table-driven |
| Static | vet, lint, format | `go vet`, pinned `golangci-lint`, wrapped `gofmt -l` |
| Smoke | Binary stdout in the distroless image | `docker run` + string equality assertion |
| Scan | Image CVEs | Trivy, report-only, non-gating |

RED-first order (`strict_tdd: true`): write `main_test.go` calling `greeting()` → fails to compile (RED) → extract → GREEN.

## Threat Matrix

N/A — no routing, VCS/PR automation, executable-file classification, or dynamic command composition. CI `run:` steps are static workflow literals over trusted repo-local inputs; no untrusted value reaches a shell.

## Migration / Rollout

No migration, no state, no runtime dependency (`go.mod` stays stdlib-only). **Rollback is trivially a `git revert` of one commit**: restore the four `ci.yml` job blocks, delete `.golangci.yml` and `main_test.go`, inline `greeting()` back into `main()`. Partial rollback is also safe — each job block is independently removable. Confirms the proposal's rollback plan.

## Open Questions

- [ ] Pin exact tags at apply time and verify the pair: `golangci/golangci-lint-action@v8` requires golangci-lint **v2.x** and the `version: "2"` config schema. If a v1.x binary is pinned instead, the action and `.golangci.yml` must both drop to the legacy schema.
- [ ] Confirm `docker/build-push-action@v6` (no `setup-buildx-action` step) still loads `go-hadolint-poc:ci` into the local image store — the current smoke test already depends on this, and Trivy will too.
