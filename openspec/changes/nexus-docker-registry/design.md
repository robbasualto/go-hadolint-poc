# Design: Nexus Docker Registry — `go-hadolint-poc` side

> Cross-repo change, revised. The registry side is **not** `nexus-k8s` (that Nexus was never installed — see below). It's the Nexus already running in `lab-devops`'s own `stacks/nexus`, reached through the ARC self-hosted runner (`lab-devops`'s `stacks/github-runner-scale-set`, label `lab-runner`). This doc consumes what's already live and verified there; it does not design any new registry/runner/TLS infrastructure.

## Revision note (supersedes the original design)

The original version of this doc assumed: registry provisioned by `nexus-k8s` (never installed), host resolved via `minikube ip` at job runtime, a new `deployer` credential delivered as GitHub Actions secrets, and a runner labeled `self-hosted,minikube`. All four assumptions are wrong. What actually exists, verified live in `lab-devops`:

- Registry: `172.19.0.5:30083`, HTTPS with a self-signed cert (archived `lab-devops` change `2026-08-17-add-nexus-tls`, verify-report PASS). Port `30082` (plain HTTP) still exists but MUST NOT be used.
- Runner: ARC (`actions-runner-controller`) ephemeral pods, label `lab-runner` (verified this session, run `31923057373`, success).
- TLS trust: already baked into the runner pod's DinD sidecar (`/etc/docker/certs.d/172.19.0.5:30083/ca.crt`) — nothing for this repo to configure.
- Credentials: already injected as **pod-level environment variables** on every `lab-runner` job — `NEXUS_DOCKER_PUSH_USERNAME`, `NEXUS_DOCKER_PUSH_PASSWORD`, `NEXUS_REGISTRY_HOST` (= `172.19.0.5:30083`). These are **not** GitHub Actions secrets; no secret needs to be created in this repo's settings.

Net effect: this is a much smaller change than originally scoped. No resolve-endpoint step, no new secret plumbing, no TLS work. The only real design decision left is how `ci.yml`/`release.yml` consume env vars that are already sitting in the job's environment — and the fork-PR exposure consequence of that, which is now *worse* than originally modeled (see Decision 5).

## Technical Approach

Zero Go changes; two YAML surfaces. **Go package/layer boundaries: not applicable.** The existing job DAG in `ci.yml` is preserved: every job (`go-build-test`, `go-lint`, `hadolint`, `gitleaks`, `docker-build`) moves to the self-hosted runner; `docker-build` alone gains login → push. `release.yml` stays one sequential job and moves wholesale.

## Architecture Decisions

| # | Decision | Choice | Rejected | Rationale |
|---|---|---|---|---|
| 1 | Runner placement | `runs-on: lab-runner` on all five `ci.yml` jobs and the whole `release` job — explicit user requirement, not a Nexus-reachability necessity | Only `docker-build`/`release` on the runner | Unchanged from the original requirement: the user wants the entire pipeline on the self-hosted runner. **Revised consequence**: because `NEXUS_DOCKER_PUSH_USERNAME`/`PASSWORD` are ambient pod-level env vars (not GitHub secrets scoped to a step), every job on `lab-runner` — including `go-build-test`/`go-lint`/`hadolint`/`gitleaks` on a fork PR — can read them, not just `docker-build`. This widens the accepted fork-PR exposure beyond what the original design modeled (which assumed GitHub's secret-withholding protected non-publish jobs). Still accepted, per the existing "Out of Scope: fork-PR hardening" line in the nexus-k8s proposal, but the exposure is now ambient-env-var-wide, not secret-scoped. ARC's scale-set may run more than one pod concurrently (autoscaling), so the "single runner, serial queue" assumption from the original design is no longer asserted as fact — not verified either way, not load-bearing for this change. |
| 2 | Host/credential source | Read `$NEXUS_REGISTRY_HOST`, `$NEXUS_DOCKER_PUSH_USERNAME`, `$NEXUS_DOCKER_PUSH_PASSWORD` directly from the job environment (already present on every `lab-runner` pod) | `minikube ip` resolve step; GitHub Actions secrets `NEXUS_DEPLOYER_USERNAME/PASSWORD` | Both are gone: there's no `minikube` on an ARC pod, and the credential is already delivered pod-side via Vault → ESO → env var by `lab-devops`. Nothing to resolve, nothing to configure in this repo's GitHub settings. If the env var is unset (misconfigured runner), the workflow MUST fail loudly rather than push to an empty host. |
| 3 | Push shape | Keep `docker/build-push-action@v6` with `push: false`, then an explicit `docker push "$IMAGE"` step **after** smoke test and Trivy | `push: true` on the build action | Unchanged from the original design: publish stays a single, last, reviewable/revertible step; smoke test stays hermetic. |
| 4 | Tag source | `github.ref_name` on release; `${GITHUB_SHA::7}` on CI | `github.run_number`; full SHA | Unchanged. On `pull_request`, `github.sha` is the merge commit rather than the PR head — accepted and documented. |
| 5 | Publish applicability | Resolve/push guarded by `if: github.event_name != 'pull_request' \|\| github.event.pull_request.head.repo.full_name == github.repository` | Unguarded | **Rationale changed, guard kept.** Originally this guard existed because GitHub withholds *secrets* from fork-PR runs, so an unguarded push would just fail on missing creds. That's no longer true — the creds are ambient pod env vars, always present. The guard now exists for a stronger reason: fork-originated code MUST NOT be allowed to push to the registry at all, credentials or not. This is now a trust boundary, not a convenience. |
| 6 | Credential handling | No `docker login` needed as a distinct step with secret plumbing — `docker login "$NEXUS_REGISTRY_HOST" -u "$NEXUS_DOCKER_PUSH_USERNAME" --password-stdin <<< "$NEXUS_DOCKER_PUSH_PASSWORD"`, reading already-present env vars; `docker logout` with `if: always()` | Declaring new `env:`-mapped GitHub secrets (`NEXUS_DEPLOYER_USERNAME/PASSWORD`) | There is nothing to map from GitHub secrets — the vars already exist in the shell. `--password-stdin` avoids `-p` process-list leakage, same as the original design. `logout` on `always()` keeps `~/.docker/config.json` clean between ephemeral-pod job runs (moot if the pod is destroyed after one job, but harmless and cheap to keep for defense-in-depth if pod reuse is ever introduced). |
| 7 | TLS / registry trust | No workflow-level TLS handling at all — the DinD sidecar already trusts `172.19.0.5:30083` via a pre-mounted CA (`lab-devops` `add-nexus-tls`) | Any `insecure-registries` config, cert distribution, or trust setup from this repo | Out of this repo's scope entirely; it's infrastructure lab-devops already owns and has verified. Documented here only so a future reader doesn't go looking for it in this repo. |

## Sequence: `ci.yml` (all jobs self-hosted)

```
push / pull_request
   │  runner: lab-runner (ARC ephemeral pod; NEXUS_REGISTRY_HOST/NEXUS_DOCKER_PUSH_* already in env)
   ▼ go-build-test   (runs-on: lab-runner, unchanged steps)
   ▼ go-lint          (runs-on: lab-runner, unchanged steps)
   ▼ hadolint         (runs-on: lab-runner, unchanged steps)
   ▼ gitleaks         (runs-on: lab-runner, unchanged steps)
   │  all green
   ▼ docker-build   runs-on: lab-runner
   checkout
     → [publish?] IMAGE="$NEXUS_REGISTRY_HOST/go-hadolint-poc:${GITHUB_SHA::7}"   (no resolve step — env var already set)
     → [publish?] docker login "$NEXUS_REGISTRY_HOST"  (NEXUS_DOCKER_PUSH_USERNAME/PASSWORD, --password-stdin)
     → build-push-action  push:false  tags:$IMAGE
     → docker run --rm "$IMAGE"  ⇒ stdout == "Hello, world!"
     → Trivy (report-only, continue-on-error)
     → [publish?] docker push "$IMAGE"        ← any earlier non-zero skips this
     → [always]   docker logout "$NEXUS_REGISTRY_HOST"
   │
   ▼
Nexus docker-hosted  (172.19.0.5:30083, HTTPS, trust pre-provisioned by lab-devops)

[publish?] = not a fork PR — trust boundary, not a credential-availability check (see Decision 5).
```

`release.yml` is the same tail on one job: existing gates → build `$IMAGE` with `<tag> = github.ref_name` → smoke test → `docker push` → **then** `gh release create`. Push precedes the Release so a tag never advertises an image that was never published.

## File Changes

| File | Action | Description |
|---|---|---|
| `.github/workflows/ci.yml` | Modify | `runs-on: lab-runner` on all five jobs. `docker-build` gains login, registry-qualified tag from env vars, explicit push, logout, publish guard. No resolve step. |
| `.github/workflows/release.yml` | Modify | `runs-on: lab-runner`; same login/tag/push chain inserted between the smoke test and `gh release create`. No guard needed — tags cannot be pushed from a fork. |
| `README.md` | Create | Repo has no README. Records the published image ref format, that credentials/TLS/registry host are provided ambiently by the `lab-runner` environment (no local setup needed), and the accepted fork-PR / self-hosted-runner exposure (now ambient-env-var-wide per Decision 1/5). |

## Testing Strategy

| Layer | What | How |
|---|---|---|
| Unit | — | No Go source touched; `go test ./...` MUST stay green. |
| Static | No `${{ }}` inside any `run:` body; no `-p` on `docker login`; push step is last; guard expression present; no `minikube` references anywhere | Read both workflows |
| Pipeline | Branch push publishes a short-SHA image to `172.19.0.5:30083`; all pre-existing gates still pass | Throwaway branch; verify in the Nexus UI |
| Pipeline | A forced gate failure (e.g. broken `gofmt`) skips the push and publishes nothing | Throwaway branch; assert no new image |
| Pipeline | Fork-PR-shaped dry run is green with the publish steps *skipped* | Fork PR or fork-shaped dry run |
| Pipeline | `v*` tag publishes the image **and** still creates the GitHub Release | Real tag push; `gh release list` + Nexus UI |
| Pipeline | Nexus down ⇒ push fails loudly, non-zero, error visible | Scale the `stacks/nexus` deployment to 0, push a branch |

## Threat Matrix

| Boundary | Applicability | Design response | Planned RED tests |
|---|---|---|---|
| Documentation-like paths | N/A | — | — |
| Git repository selection | **Applicable** | Only `actions/checkout` in `GITHUB_WORKSPACE`; no `git -C`, no relative-path resolution. Ephemeral ARC pods start clean per job, so no cross-run staleness concern (unlike a persistent runner). | N/A — pod lifecycle already guarantees this |
| Commit state | N/A — workflows never stage or commit | — | — |
| Push state | **Applicable** | Zero `git push`. Registry push is one explicit, last step against `$NEXUS_REGISTRY_HOST`; empty/unset env var MUST abort before `docker push` | Unset `NEXUS_REGISTRY_HOST` ⇒ non-zero, no push attempted |
| PR commands | **Applicable** | Every value (`github.ref_name`, both credential env vars) reaches `run:` via `env:`/shell expansion and is used as `"$VAR"` — never interpolated into a script body | A branch/tag name containing shell metacharacters MUST NOT execute |
| Ambient credential exposure (new — see Decision 1/5) | **Applicable** | Fork-PR-triggered jobs on `lab-runner` MUST NOT run the publish steps, since the credentials are ambient env vars available to the whole pod, not gated by GitHub secret-withholding | A fork-PR-shaped run MUST show the publish steps skipped (guard evaluated `false`), not merely a failed login |
| Shell/subprocess (`docker`) | **Applicable** | `docker` resolved from the runner pod's `PATH`; credentials on stdin only; `docker logout` on `if: always()` | Missing `docker` on `PATH` ⇒ clear non-zero failure |

## Migration / Rollout

No cross-repo landing order dependency anymore — the registry, runner, and TLS trust already exist and are live. Rollback is a single `git revert`: `push: false` and `ubuntu-latest` return, nothing to clean up. `go.mod` stays empty; no runtime dependency is added.

## Open Questions

- [ ] Confirm whether `NEXUS_DOCKER_PUSH_USERNAME`/`PASSWORD` grant push-only (no delete) — matches `lab-devops`'s stated least-privilege intent for that credential, but re-confirm before writing the README's security note as fact.
- [ ] `nexus-k8s`'s `openspec/changes/nexus-docker-registry/` (the old Phase A, uncommitted, targets a Nexus that was never installed) should be explicitly archived/abandoned by the user — out of this repo's control, flagged here so it isn't lost.
