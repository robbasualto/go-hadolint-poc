# Design: Nexus Docker Registry — `go-hadolint-poc` side

> Cross-repo change. **Proposal**: `nexus-k8s/openspec/changes/nexus-docker-registry/proposal.md`.
> **Registry-side design (owns the Integration Contract)**: `nexus-k8s/openspec/changes/nexus-docker-registry/design.md`.
> Two design docs, one per repo, so each ships as an independently reviewable and independently revertible PR. This doc *consumes* the contract (host `$(minikube ip):30082`, flat image ref, `deployer` Basic auth) and does not restate it.

## Technical Approach

Zero Go changes; two YAML surfaces. **Go package/layer boundaries: not applicable** — no Go source is touched, no package is added. The existing job DAG in `ci.yml` is preserved: every job (`go-build-test`, `go-lint`, `hadolint`, `gitleaks`, `docker-build`) moves to the self-hosted runner; `docker-build` alone gains resolve → login → push. `release.yml` stays one sequential job and moves wholesale, since its gates and its build live in the same job and splitting them would require artifact passing or a rebuild.

## Architecture Decisions

| # | Decision | Choice | Rejected | Rationale |
|---|---|---|---|---|
| 1 | Runner placement | `runs-on: [self-hosted, minikube]` on **all five jobs** in `ci.yml` (`go-build-test`, `go-lint`, `hadolint`, `gitleaks`, `docker-build`) and the whole `release` job in `release.yml` — explicit user requirement, not a Nexus-reachability necessity | Only `docker-build`/`release` self-hosted | The user explicitly required the entire pipeline to run on the self-hosted runner, overriding the narrower "only jobs that touch the registry" default. Consequence, stated plainly: a single runner executes one job at a time, so `ci.yml`'s independent jobs (previously parallel across separate `ubuntu-latest` runners) now queue and run serially — CI wall-clock time increases with pipeline size. It also widens the accepted fork-PR exposure to every job, not just the one touching Nexus (already an accepted risk, unchanged in kind, widened in surface). A custom `minikube` label makes the requirement explicit and survives a second runner. |
| 2 | Host resolution (D3) | A `run:` step executing `minikube ip`, publishing `host` and `image` as step outputs | Hardcoded IP; `/etc/hosts` alias; a repo variable | Minikube's IP is unstable across recreates; resolving per run is self-healing. An alias would still need a manual edit on every client. The step MUST fail loudly when `minikube ip` is empty rather than emitting a bare `:30082`. |
| 3 | Push shape | Keep `docker/build-push-action@v6` with `push: false`, then an explicit `docker push "$IMAGE"` step **after** smoke test and Trivy | `push: true` on the build action | Satisfies "push runs after all existing gates" literally, keeps the smoke test hermetic (no registry round trip), and makes the publish a single reviewable, single-revertible step. No `setup-buildx` step is added, so the docker driver keeps building straight into the local image store exactly as today. |
| 4 | Tag source | `github.ref_name` on release; `${GITHUB_SHA::7}` on CI | `github.run_number`; full SHA | Matches D3. On `pull_request`, `github.sha` is the merge commit rather than the PR head — accepted and documented; the tag stays unique and traceable. |
| 5 | Publish applicability | Resolve/login/push/logout guarded by `if: github.event_name != 'pull_request' \|\| github.event.pull_request.head.repo.full_name == github.repository` | Unguarded | GitHub withholds secrets from fork-PR runs, so an unguarded `docker login` turns every fork PR red on missing creds. Skipping the publish path is push *applicability*, not fork hardening: forks still build, smoke test and scan. |
| 6 | Credential handling | `echo "$PASS" \| docker login "$HOST" -u "$USER" --password-stdin`, secrets injected via `env:`; `docker logout "$HOST"` with `if: always()` | `docker login -p`; `${{ }}` interpolated into a `run:` body | `-p` leaks the password into the process list and a deprecation warning. Interpolating into `run:` is the script-injection boundary already established by `pipeline-hardening` decision 6. `logout` on `always()` keeps `~/.docker/config.json` clean on a persistent runner between jobs. |
| 7 | Secret names | `NEXUS_DEPLOYER_USERNAME` / `NEXUS_DEPLOYER_PASSWORD` | `NEXUS_DEPLOYER_USER` | The signed proposal and the spec delta both use `…_USERNAME`; the launch brief's `…_USER` was illustrative. One name, everywhere. |

## Sequence: `ci.yml` (all jobs self-hosted)

```
push / pull_request
   │  runner: [self-hosted, minikube] — single runner, jobs queue and run one at a time
   ▼ go-build-test   (runs-on: [self-hosted, minikube], unchanged steps)
   ▼ go-lint          (runs-on: [self-hosted, minikube], unchanged steps)
   ▼ hadolint         (runs-on: [self-hosted, minikube], unchanged steps)
   ▼ gitleaks         (runs-on: [self-hosted, minikube], unchanged steps)
   │  all green
   ▼ docker-build   runs-on: [self-hosted, minikube]
   checkout
     → [publish?] resolve endpoint:  HOST=$(minikube ip):30082
                                     IMAGE=$HOST/go-hadolint-poc:${GITHUB_SHA::7}
     → [publish?] docker login $HOST  (deployer, --password-stdin)
     → build-push-action  push:false  tags:$IMAGE
     → docker run --rm "$IMAGE"  ⇒ stdout == "Hello, world!"
     → Trivy (report-only, continue-on-error)
     → [publish?] docker push "$IMAGE"        ← any earlier non-zero skips this
     → [always]   docker logout "$HOST"
   │
   ▼
Nexus docker-hosted  (NodePort 30082)

[publish?] = not a fork PR.
```

`release.yml` is the same tail on one job: existing gates → build `$IMAGE` with `<tag> = github.ref_name` → smoke test → `docker push` → **then** `gh release create`. Push precedes the Release so a tag never advertises an image that was never published.

## File Changes

| File | Action | Description |
|---|---|---|
| `.github/workflows/ci.yml` | Modify | `runs-on: [self-hosted, minikube]` on all five jobs. `docker-build` additionally gains resolve step, login, registry-qualified tag, explicit push, logout, publish guard. |
| `.github/workflows/release.yml` | Modify | `runs-on: [self-hosted, minikube]`; same resolve/login/tag/push chain inserted between the smoke test and `gh release create`. No guard needed — tags cannot be pushed from a fork. |
| `README.md` | Create | Repo has no README. Records the published image ref, the `insecure-registries` prerequisite for pulling, and the **accepted fork-PR / self-hosted-runner exposure** (a success criterion requires this to live in repo docs, not only in the proposal). |

## Testing Strategy

| Layer | What | How |
|---|---|---|
| Unit | — | No Go source touched; `strict_tdd` targets Go code and none changes. `go test ./...` MUST stay green. |
| Static | No `${{ }}` inside any `run:` body; no `-p` on `docker login`; push step is last; guard expression present | Read both workflows |
| Pipeline | Branch push publishes a short-SHA image; all pre-existing gates still pass | Throwaway branch; verify in the Nexus UI |
| Pipeline | A forced gate failure (e.g. broken `gofmt`) skips the push and publishes nothing | Throwaway branch; assert no new image |
| Pipeline | Fork PR is green with the publish steps *skipped* | PR from a fork or a fork-shaped dry run |
| Pipeline | `v*` tag publishes the image **and** still creates the GitHub Release | Real tag push; `gh release list` + Nexus UI |
| Pipeline | Nexus down ⇒ push fails loudly, non-zero, error visible | Scale the deployment to 0, push a branch |

## Threat Matrix

| Boundary | Applicability | Design response | Planned RED tests |
|---|---|---|---|
| Documentation-like paths | N/A — no file classification or execution routing | — | — |
| Git repository selection | **Applicable** | Only `actions/checkout` in `GITHUB_WORKSPACE`; no `git -C`, no relative-path resolution. On a **persistent** self-hosted runner the workspace is reused across runs — checkout MUST NOT be assumed clean. | Consecutive runs of different refs on the same runner leave no stale artifact |
| Commit state | N/A — workflows never stage or commit | — | — |
| Push state | **Applicable** | Zero `git push`. Registry push is one explicit, last step against a runtime-resolved host; empty `minikube ip` MUST abort before `docker push` | Empty/failing `minikube ip` ⇒ non-zero, no push attempted |
| PR commands | **Applicable** | Every `${{ }}` value (`github.ref_name`, step outputs, both secrets) reaches `run:` via `env:` and is used as `"$VAR"` — never interpolated into a script body | A branch/tag name containing shell metacharacters MUST NOT execute |
| Shell/subprocess (`minikube`, `docker`) | **Applicable** | `minikube` and `docker` resolved from the runner service user's `PATH` and `docker` group; credentials on stdin only; `docker logout` on `if: always()` | Missing `minikube` on `PATH` ⇒ clear non-zero failure, not a bare `:30082` tag |

## Migration / Rollout

Lands **after** the `nexus-k8s` PR — the connector does not exist until the registry side is deployed and provisioned. Rollback is a single `git revert`: `push: false` and `ubuntu-latest` return, nothing to clean up. The runner and the two secrets are removed from repo settings independently. `go.mod` stays empty; no runtime dependency is added.

## Open Questions

- [ ] Decision 5's fork-PR guard skips the login step, so the spec scenario "Login fails with invalid or missing credentials" applies only to non-fork runs. `sdd-tasks` MUST carry a one-line reconciliation to `specs/docker-image-publish/spec.md`.
- [ ] The exact self-hosted runner label set depends on registration; the workflows MUST be written against `[self-hosted, minikube]` and the runbook MUST register with `--labels minikube`.
