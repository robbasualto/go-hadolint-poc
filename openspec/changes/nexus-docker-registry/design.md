# Design: Nexus Docker Registry — `go-hadolint-poc` side

> Cross-repo change, revised three times. Rev 1: the registry side is **not** `nexus-k8s` (never installed) — it's the Nexus already live in `lab-devops`'s `stacks/nexus`, reached through ARC's `lab-runner`. Rev 2: migrated `go-build-test`/`go-lint`/`hadolint`/`gitleaks` to `robbasualto/pipelines@v1.0.1`'s reusable workflows instead of local duplicated steps, and tried splitting `docker-build` (generic, via `pipelines`) from Nexus publish (a new local file) into two jobs. Rev 3 (this one): the two-job split was reverted — publish is folded back into a single local `docker-build` job, because splitting it forced the image to be built twice (ARC's `lab-runner` is one ephemeral pod per job, nothing shared between them). `go-build-test`/`go-lint`/`hadolint`/`gitleaks` stay migrated to `pipelines`; only `docker-build` stays local, since it's the one job that needs registry-specific behavior `pipelines`'s generic `docker-build.yml` deliberately doesn't carry.

## Revision 1 note (registry/runner/TLS reality)

- Registry: `172.19.0.5:30083`, HTTPS with a self-signed cert (archived `lab-devops` change `2026-08-17-add-nexus-tls`, verify-report PASS). Port `30082` (plain HTTP) still exists but MUST NOT be used.
- Runner: ARC (`actions-runner-controller`) ephemeral pods, label `lab-runner` — one pod per job, nothing persists or shares filesystem across jobs.
- TLS trust: already baked into the runner pod's DinD sidecar (`/etc/docker/certs.d/172.19.0.5:30083/ca.crt`) — nothing for this repo to configure.
- Credentials: already injected as **pod-level environment variables** on every `lab-runner` job — `NEXUS_DOCKER_PUSH_USERNAME`, `NEXUS_DOCKER_PUSH_PASSWORD`, `NEXUS_REGISTRY_HOST` (= `172.19.0.5:30083`). Not GitHub Actions secrets.

## Revision 2 note (pipelines migration, kept)

`robbasualto/pipelines@v1.0.1` ships reusable `workflow_call` workflows for `go-build-test`, `go-lint`, `hadolint`, `gitleaks`, and a generic `docker-build` (build+smoke+Trivy, `push: false`, registry-agnostic). `go-build-test`/`go-lint`/`hadolint`/`gitleaks` now call these instead of duplicating step-level logic. **Nexus publish logic still MUST NOT be folded into `pipelines`'s generic `docker-build.yml`** — that workflow stays reusable for any future service, Nexus or not.

## Revision 3 note (publish folded back into `docker-build`, single job)

Rev 2 tried the opposite: keep `pipelines`'s generic `docker-build.yml` for build/smoke/Trivy, and push Nexus-specific login/push/logout into a brand-new separate local file (`nexus-publish.yml`) as its own job. That satisfied "don't touch `pipelines`'s workflow" but cost a second, redundant image build — `pipelines`'s reusable-workflow call is its own job, hence its own ARC pod, hence its own DinD sidecar with nothing in common with any sibling job. Confirmed: `gh api .../actions/runners` shows zero persistent runners right after a run — pods really are one-shot.

Given that real cost, `docker-build` is **not** delegated to `pipelines` at all. It stays a single local job — build, smoke test, Trivy scan, and (guarded) Nexus login/push/logout — exactly as in Rev 1, just with the other four jobs (`go-build-test`/`go-lint`/`hadolint`/`gitleaks`) still migrated. This is the smallest correct design: one build, one job, no job-output plumbing needed to pass an image tag across a job boundary that no longer exists.

## Technical Approach

Zero Go changes. `ci.yml`/`release.yml` are the only two files touched (plus `README.md`). `go-build-test`, `go-lint`, `hadolint`, `gitleaks` are thin `uses:` calls into `robbasualto/pipelines@v1.0.1`. `docker-build` (`ci.yml`) / `release` (`release.yml`) stay local, single-job, doing build → smoke test → Trivy → (guarded) Nexus login/push/logout. **Go package/layer boundaries: not applicable.**

## Architecture Decisions

| # | Decision | Choice | Rejected | Rationale |
|---|---|---|---|---|
| 1 | Runner placement | `runner: lab-runner` on every `pipelines` call; `runs-on: lab-runner` on the local `docker-build`/`release` job — explicit user requirement | Only the publish step on the runner | Unchanged requirement: entire pipeline on the self-hosted runner. Ambient pod-level credentials mean every job on `lab-runner` can read them, not just the one that publishes — accepted, unchanged from Rev 1/2. |
| 2 | Local vs. shared logic | `go-build-test`, `go-lint`, `hadolint`, `gitleaks` call `robbasualto/pipelines/.github/workflows/*.yml@v1.0.1`; `docker-build`/`release` stay entirely local | Also delegate `docker-build` to `pipelines`'s generic workflow (Rev 2) | Delegating `docker-build` would force a second job (Decision 3 below explains why that's expensive) just to keep Nexus-specific code out of `pipelines`. Keeping it local avoids the split without ever writing Nexus logic into the shared repo — `pipelines`'s `docker-build.yml` stays untouched and reusable for any future service. |
| 3 | One job, not two (superseded from Rev 2) | Build, smoke test, Trivy, and publish all in one `docker-build`/`release` job | Two jobs (generic build via `pipelines` + a separate local publish job/file), joined by `needs:` and a job-output-carried image tag | Rev 2's two-job split cost a full second `docker build` per run — ARC's `lab-runner` is one ephemeral pod per job; nothing built in one job exists in another. One job means one build, and the image tag never needs to cross a job boundary (no `resolve-image` job, no job outputs) — it's just a shell variable for the whole job's lifetime. |
| 4 | Host/credential source | Read `$NEXUS_REGISTRY_HOST`, `$NEXUS_DOCKER_PUSH_USERNAME`, `$NEXUS_DOCKER_PUSH_PASSWORD` directly from the job environment (already present on every `lab-runner` pod) | `minikube ip` resolve step; GitHub Actions secrets | No `minikube` on an ARC pod; credential already delivered pod-side via Vault → ESO → env var by `lab-devops`. The job's first step fails loudly if `NEXUS_REGISTRY_HOST` is unset rather than push to an empty host. |
| 5 | Publish applicability | Login/push/logout steps individually guarded: `if: github.event_name != 'pull_request' \|\| github.event.pull_request.head.repo.full_name == github.repository` | Job-level guard (Rev 2, only possible because publish was a separate job) | With publish back inside `docker-build`, the guard has to live on the individual steps again — build/smoke/Trivy still run for fork PRs, only login/push/logout are skipped. Trust boundary, not a credential-availability check: fork code must never publish, credentials or not. |
| 6 | Credential handling | `docker login "$NEXUS_REGISTRY_HOST" -u "$NEXUS_DOCKER_PUSH_USERNAME" --password-stdin`, `::add-mask::` on the password (matches the already-proven pattern in `test-nexus-push.yml`); `docker logout` with `if: always() && <guard>` | New GitHub-secret-mapped credentials | Nothing to map — vars already exist in the shell. `--password-stdin` avoids `-p` process-list leakage. Logout guard combines `always()` with the same publish condition so it only fires when login actually ran. |
| 7 | TLS / registry trust | No workflow-level TLS handling — the DinD sidecar already trusts `172.19.0.5:30083` via a pre-mounted CA (`lab-devops` `add-nexus-tls`) | Any `insecure-registries`/cert work from this repo | Out of this repo's scope; `lab-devops`-owned and verified. |
| 8 | Pinning | `robbasualto/pipelines/...@v1.0.1` (exact tag, not `@v1` floating) | Floating major tag | Matches this repo's existing pin-everything convention. |

## Sequence: `ci.yml`

```
push / pull_request
   │
   ├─▶ go-build-test  (pipelines/go-build-test.yml@v1.0.1, runner: lab-runner)
   ├─▶ go-lint         (pipelines/go-lint.yml@v1.0.1, runner: lab-runner)
   ├─▶ hadolint        (pipelines/hadolint.yml@v1.0.1, runner: lab-runner)
   └─▶ gitleaks        (pipelines/gitleaks.yml@v1.0.1, runner: lab-runner)
              │  needs: [go-build-test, go-lint, hadolint]
              ▼
        docker-build   runs-on: lab-runner (single local job)
        checkout
          → IMAGE="$NEXUS_REGISTRY_HOST/go-hadolint-poc:${GITHUB_SHA::7}"   (fail loudly if unset)
          → [publish?] docker login "$NEXUS_REGISTRY_HOST"
          → build-push-action  push:false  tags:$IMAGE
          → docker run --rm "$IMAGE"  ⇒ stdout == "Hello, world!"
          → Trivy (report-only, continue-on-error)
          → [publish?] docker push "$IMAGE"
          → [always, publish?] docker logout "$NEXUS_REGISTRY_HOST"
              │
              ▼
        Nexus docker-hosted (172.19.0.5:30083, HTTPS, trust pre-provisioned by lab-devops)

[publish?] = not a fork PR — trust boundary, not a credential-availability check.
```

`release.yml` is the same shape: `go-build-test`/`go-lint`/`hadolint` via `pipelines`, then one local `release` job doing build → smoke test → **unconditional** login/push (tags cannot come from a fork) → `gh release create`. Push precedes Release creation so a tag never advertises an unpublished image. No `gitleaks` in `release.yml` (unchanged from before this whole effort — matches the original repo's job set).

## File Changes

| File | Action | Description |
|---|---|---|
| `.github/workflows/ci.yml` | Rewrite | `go-build-test`/`go-lint`/`hadolint`/`gitleaks` delegate to `pipelines@v1.0.1`; `docker-build` stays local, gains login/push/logout. |
| `.github/workflows/release.yml` | Rewrite | Same delegation pattern; single local `release` job does build/smoke/login/push/logout/`gh release create`. |
| `README.md` | Create | Published image ref format, ambient env vars, accepted fork-PR exposure note. |

## Testing Strategy

| Layer | What | How |
|---|---|---|
| Unit | — | No Go source touched; `go test ./...` MUST stay green. |
| Static | No `${{ }}` inside any `run:` body; no `-p` on `docker login`; push step guarded and last; logout guarded with `always()`; no `minikube` references; both files YAML-valid | Read both files |
| Pipeline | Branch push publishes a short-SHA image to `172.19.0.5:30083`; all pre-existing gates still pass | Throwaway branch; verify in the Nexus UI |
| Pipeline | A forced gate failure (e.g. broken `gofmt`) blocks `docker-build` via `needs:`, publishes nothing | Throwaway branch; assert no new image |
| Pipeline | Fork-PR-shaped dry run: `docker-build` builds/smoke-tests/scans but login/push/logout are skipped | Fork PR or fork-shaped dry run |
| Pipeline | `v*` tag publishes the image **and** still creates the GitHub Release, in that order | Real tag push; `gh release list` + Nexus UI |
| Pipeline | Nexus down ⇒ push fails loudly, non-zero, error visible | Scale `lab-devops`'s `stacks/nexus` deployment to 0, push a branch |

## Threat Matrix

| Boundary | Applicability | Design response | Planned RED tests |
|---|---|---|---|
| Documentation-like paths | N/A | — | — |
| Git repository selection | **Applicable** | Only `actions/checkout` in `GITHUB_WORKSPACE`; ephemeral ARC pods start clean per job | N/A — pod lifecycle guarantees this |
| Commit state | N/A | — | — |
| Push state | **Applicable** | Zero `git push`. Registry push is one explicit step against `$NEXUS_REGISTRY_HOST`; empty/unset env var MUST abort the job before any docker command runs | Unset `NEXUS_REGISTRY_HOST` ⇒ non-zero, no push attempted |
| PR commands | **Applicable** | Every value reaching a `run:` body uses shell expansion (`$VAR`) or GitHub's own default env vars (`$GITHUB_SHA`, `$GITHUB_REF_NAME`), never a raw `${{ }}` interpolation inside a script body | A branch/tag name containing shell metacharacters MUST NOT execute |
| Ambient credential exposure | **Applicable** | Fork-PR-triggered jobs on `lab-runner` MUST NOT run login/push/logout, since the credentials are ambient env vars available to the whole pod | A fork-PR-shaped run MUST show the publish steps skipped, not merely a failed login |
| Reusable workflow supply chain | **Applicable** | `pipelines` calls are pinned to an exact tag (`@v1.0.1`), not a branch or floating major | A `pipelines` tag bump requires an explicit version-string change in this repo, never silent |
| Shell/subprocess (`docker`) | **Applicable** | `docker` resolved from the runner pod's `PATH`; credentials on stdin only | Missing `docker` on `PATH` ⇒ clear non-zero failure |

## Migration / Rollout

No cross-repo landing order dependency — the registry, runner, TLS trust, and `pipelines@v1.0.1` all already exist and are live/tagged. Rollback is a single `git revert` per file. `go.mod` stays empty; no runtime dependency is added.

## Open Questions

- [ ] Confirm whether `NEXUS_DOCKER_PUSH_USERNAME`/`PASSWORD` grant push-only (no delete) — re-confirm before treating it as fact in the README.
- [ ] `nexus-k8s`'s `openspec/changes/nexus-docker-registry/` (old Phase A, uncommitted, targets a Nexus that was never installed) should be explicitly archived/abandoned by the user.
- [ ] If `docker-build`'s inline steps ever grow enough to feel worth sharing, consider proposing a *Nexus-aware* reusable workflow addition to `pipelines` itself (a real new capability there, not a local one-off) — out of scope for this change.
