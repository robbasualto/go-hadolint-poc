# Design: Pipeline Hardening

## Technical Approach

Two additive YAML surfaces, zero Go changes. `ci.yml` gains one independent `gitleaks` job (no `needs:`, so it cannot alter the existing DAG). A new `release.yml` runs one sequential job on `v*` tag pushes: gates → image build → smoke test → `gh release create`. Go package/layer boundaries are **not applicable** — no Go code, no new package.

## Architecture Decisions

| # | Decision | Choice | Rejected | Rationale |
|---|---|---|---|---|
| 1 | gitleaks placement | New top-level job `gitleaks` in `ci.yml`, no `needs:`, inherits `push`/`pull_request`; `actions/checkout@v4` with `fetch-depth: 0`; `gitleaks/gitleaks-action` pinned to a concrete `v3.x.y` | Adding it as a step inside `go-build-test`; making `docker-build` depend on it | Independence keeps rollback to a single deletable block and preserves the existing 4-job DAG. `fetch-depth: 0` is required: the default shallow checkout hides historical leaks. |
| 2 | Release gate logic | **Duplicate** ci.yml's step logic inline in `release.yml` | `workflow_call` reusable workflow; composite action | Confirms proposal risk #3. Extraction would have to modify `ci.yml` (proposal guarantees the 4 jobs are untouched) and buys abstraction for two consumers. Revisit at a third consumer. |
| 3 | Release job shape | One job `release`, steps strictly sequential | Parallel gate jobs + a `needs:`-gated release job | Fail-fast falls out of step semantics; avoids repeat checkout/setup and artifact passing. Cost: no parallelism, accepted. |
| 4 | Permissions | `permissions: contents: write` declared at **job** level; `gh` receives `GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}` | Workflow-level block; a PAT secret | Least privilege scoped to the only job needing it. The default `GITHUB_TOKEN` creates Releases with `contents: write` — **no new secret**. |
| 5 | Failure semantics | Rely on default step behaviour; `gh release create` is the **last** step | An `if: success()` guard; a cleanup step deleting the tag | A non-zero step fails the job and skips remaining steps, so `if:` is redundant. Gate steps MUST NOT set `continue-on-error` or `if: always()`. Orphan tags are accepted; no auto-delete (destructive on a remote ref). |
| 6 | gitleaks licensing | No `GITLEAKS_LICENSE`. The action is free for personal accounts and public repos; `robbasualto/go-hadolint-poc` is both | Provisioning a license secret; running the `gitleaks` CLI directly | Avoids an unnecessary secret. Fallback if a pinned v3 changes terms: swap to the CLI binary — same detection, no licensing surface. |

## Sequence: release.yml

```
git push origin v0.1.0
   │
   ▼
[trigger on: push: tags: ["v*"]]
   │
   ▼ job release (permissions: contents: write)
   checkout → setup-go 1.26.5
      → go build ./...      ┐
      → go vet ./...        │ any non-zero
      → go test ./... -cover│ ⇒ job fails,
      → gofmt -l check      │ later steps
      → golangci-lint       │ SKIPPED
      → hadolint            ┘
      → docker build (push:false, tag :${GITHUB_REF_NAME})
      → docker run ⇒ stdout == "Hello, world!"
      → gh release create "$TAG" --generate-notes
   │
   ▼
GitHub Release (auto notes) — no registry, no SBOM, no signing
```

## File Changes

| File | Action | Description |
|---|---|---|
| `.github/workflows/ci.yml` | Modify | Append `gitleaks` job only; existing jobs byte-identical |
| `.github/workflows/release.yml` | Create | Tag-triggered single-job verify → build → smoke → release |
| `openspec/config.yaml` | Modify | `Repo:` line — replace "no remote" with `remote https://github.com/robbasualto/go-hadolint-poc (public), default branch master` |

Docker steps MUST mirror `ci.yml`'s proven pair (`docker/build-push-action@v6`, `push: false`, then `docker run --rm`) rather than inventing a variant.

## Testing Strategy

| Layer | What | How |
|---|---|---|
| Static | Action pins, `fetch-depth: 0`, no `v2`, no `continue-on-error` on gates | Read `ci.yml` / `release.yml` |
| Pipeline | gitleaks blocks a planted credential; passes clean history | Throwaway branch + PR |
| Pipeline | Tag `v0.1.0` produces a Release; a failing-gate tag produces none | Real tag push; verify with `gh release list` |

No Go tests change (`strict_tdd` targets Go source; none is touched).

## Threat Matrix

| Boundary | Applicability | Design response |
|---|---|---|
| Documentation-like paths | N/A — no file classification or execution routing | — |
| Git repository selection | Applicable | Only `actions/checkout` in `GITHUB_WORKSPACE`; no `git -C`, no relative-path resolution |
| Commit state | N/A — workflows never stage or commit | — |
| Push state | Applicable | Zero `git push` and zero registry push from CI; `push: false` asserted on the build action |
| PR/release commands | Applicable | Tag MUST reach `gh` via `env: TAG: ${{ github.ref_name }}` and be used as `"$TAG"` — never `${{ }}` interpolated into a `run:` body (script-injection boundary) |

## Migration / Rollout

No migration. Rollback is a `git revert` of the change commit: delete the `gitleaks` block, delete `release.yml`, revert the config hunk. No code, schema, secret, registry state, or runtime dependency involved; `go.mod` stays empty.

## Open Questions

- [ ] **Blocking at apply time**: the concrete `gitleaks-action` v3 patch tag is unresolved (no web access in this phase). Apply MUST resolve it via `gh api repos/gitleaks/gitleaks-action/releases/latest --jq .tag_name`, confirm it is `v3.x.y`, and pin that exact tag — never `v3` floating, never a guess.
- [ ] First gitleaks run may surface historical findings; triage then (rotate real leaks, `.gitleaksignore` false positives).
