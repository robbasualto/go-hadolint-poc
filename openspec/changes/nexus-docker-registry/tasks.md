# Tasks: Nexus Docker Registry — `go-hadolint-poc` side (revised)

> Originally "Phase B", blocked on a `nexus-k8s` Phase A that was never installed. That dependency is gone: the registry, runner, and TLS trust this repo needs already exist and are verified live in `lab-devops` (ARC + DinD: archived `2026-08-16-add-runner-docker-build-support`, 21/21 PASS; TLS: archived `2026-08-17-add-nexus-tls`, PASS). **No longer blocked.** `nexus-k8s`'s own `nexus-docker-registry` change should be archived/abandoned by the user separately — out of scope here.

## Review Workload Forecast

Session review budget for this change: **400 lines (skill default — no override needed anymore)**, smaller than the original 800-line forecast now that the resolve-step/new-secret/TLS work is gone.

| File | Action | Est. lines |
|---|---|---|
| `.github/workflows/ci.yml` | Modify | ~30-40 |
| `.github/workflows/release.yml` | Modify | ~20-30 |
| `README.md` | Create | ~30-45 |
| `specs/docker-image-publish/spec.md` | Modify (host/credential model) | ~10 |
| `specs/release-automation/spec.md` | Modify (host/credential model) | ~6 |
| **Total** | | **~96-131** |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: pending
400-line budget risk: Low

### Suggested Work Units

| Unit | Goal | Likely PR | Focused test command | Runtime harness | Rollback boundary |
|---|---|---|---|---|---|
| 1 | Spec reconciliation (host/credential model) | PR 1 (single PR) | Read diff against `lab-devops`-confirmed env var names | — | `git revert` |
| 2 | `ci.yml` runner + publish chain | PR 1 (same PR, separate commit) | Static read (no `${{ }}` in `run:` bodies, no `-p` on login, push last, guard present, no `minikube` references) | Throwaway branch push on `lab-runner` | `git revert`: `push: false` + `ubuntu-latest` return |
| 3 | `release.yml` runner + publish chain, README | PR 1 (same PR, separate commit) | `gh release list` + Nexus UI check after a real `v*` tag | Real tag push against live Nexus | `git revert` |

## Phase 1: Spec Reconciliation

- [ ] 1.1 Edit `specs/docker-image-publish/spec.md`: replace `NEXUS_DEPLOYER_USERNAME`/`NEXUS_DEPLOYER_PASSWORD` GitHub secrets language with `NEXUS_DOCKER_PUSH_USERNAME`/`NEXUS_DOCKER_PUSH_PASSWORD` ambient runner-pod env vars; replace `<minikube-ip>:30082` with `$NEXUS_REGISTRY_HOST` (`172.19.0.5:30083`, HTTPS); replace `self-hosted` runner label references with `lab-runner`.
- [ ] 1.2 Edit `specs/release-automation/spec.md`: same host/credential-source replacements as 1.1, in the "Registry Push on Release" requirement and its scenarios.
- [ ] 1.3 `specs/ci-pipeline/spec.md`: no change needed — already generic ("self-hosted runner label", no host/credential specifics).

## Phase 2: `ci.yml`

- [ ] 2.1 Set `runs-on: lab-runner` on `go-build-test`, `go-lint`, `hadolint`, `gitleaks` (steps unchanged).
- [ ] 2.2 Set `runs-on: lab-runner` on `docker-build`.
- [ ] 2.3 `docker-build`: compute `IMAGE="$NEXUS_REGISTRY_HOST/go-hadolint-poc:${GITHUB_SHA::7}"` inline (no resolve step, no `minikube` call) — fail loudly if `NEXUS_REGISTRY_HOST` is unset.
- [ ] 2.4 `docker-build`: add publish guard `if: github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository` on login/push/logout steps.
- [ ] 2.5 `docker-build`: add `docker login "$NEXUS_REGISTRY_HOST"` step using `$NEXUS_DOCKER_PUSH_USERNAME`/`$NEXUS_DOCKER_PUSH_PASSWORD` (already in env — no `env:`-mapped GitHub secrets to declare), `--password-stdin`, no `-p`.
- [ ] 2.6 `docker-build`: update `docker/build-push-action@v6` `tags:` to `$IMAGE` (short-SHA tag), keep `push: false`.
- [ ] 2.7 `docker-build`: add explicit `docker push "$IMAGE"` step after smoke test + Trivy.
- [ ] 2.8 `docker-build`: add `docker logout "$NEXUS_REGISTRY_HOST"` with `if: always()`.

## Phase 3: `release.yml`

- [ ] 3.1 Set `runs-on: lab-runner` on the release job.
- [ ] 3.2 Insert login/tag/push chain (tag = `github.ref_name`, `IMAGE`/creds from env, no resolve step) between smoke test and `gh release create`; no fork guard needed (tags cannot come from a fork).

## Phase 4: Docs

- [ ] 4.1 Create `README.md`: published image ref format (`172.19.0.5:30083/go-hadolint-poc:<tag>`), note that registry host/credentials/TLS trust are provided ambiently by the `lab-runner` environment (nothing to configure locally or in repo secrets), and the accepted fork-PR/self-hosted-runner exposure note (ambient env vars, not GitHub-secret-scoped — see design Decision 1/5).

## Phase 5: Tests / Verification

- [ ] 5.1 Static: read both workflows — no `${{ }}` inside any `run:` body, no `-p` on `docker login`, push step is last, guard expression present, zero `minikube` references.
- [ ] 5.2 Pipeline: throwaway branch push — verify short-SHA image published to `172.19.0.5:30083`, all gates pass (check Nexus UI).
- [ ] 5.3 Pipeline: force a gate failure (e.g. broken `gofmt`) — verify push skipped, no new image.
- [ ] 5.4 Pipeline: fork-PR-shaped dry run — verify green with publish steps skipped.
- [ ] 5.5 Pipeline: real `v*` tag push — verify image pushed AND GitHub Release created.
- [ ] 5.6 Pipeline: scale `lab-devops`'s `stacks/nexus` deployment to 0, push a branch — verify push fails loudly, non-zero.

## Phase 6: Operational (not a code task)

- [x] 6.1 [Operational] Self-hosted runner already registered and verified — no manual registration needed. (Was: "register runner with labels self-hosted,minikube per nexus-k8s runbook §9" — obsolete, ARC/`lab-runner` already live.)
