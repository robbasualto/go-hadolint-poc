# Tasks: Nexus Docker Registry — `go-hadolint-poc` side (revised three times)

> Originally "Phase B", blocked on a `nexus-k8s` Phase A that was never installed — that dependency is gone (ARC + DinD: archived `2026-08-16-add-runner-docker-build-support`, 21/21 PASS; TLS: archived `2026-08-17-add-nexus-tls`, PASS in `lab-devops`). Revised to migrate `go-build-test`/`go-lint`/`hadolint`/`gitleaks` onto `robbasualto/pipelines@v1.0.1`. A two-job split (generic `docker-build` via `pipelines` + a separate local publish job) was tried and reverted — it forced a redundant second image build on ARC's ephemeral `lab-runner` pods. Final shape: those four jobs delegate to `pipelines`; `docker-build`/`release` stay a single local job each, including the Nexus publish steps. `nexus-k8s`'s own `nexus-docker-registry` change should be archived/abandoned by the user separately — out of scope here.

## Review Workload Forecast

Session review budget for this change: **400 lines (skill default)**.

| File | Action | Est. lines |
|---|---|---|
| `.github/workflows/ci.yml` | Rewrite | ~46 |
| `.github/workflows/release.yml` | Rewrite | ~48 |
| `README.md` | Create | ~40 |
| `specs/docker-image-publish/spec.md` | Modify (host/credential model) | ~10 |
| `specs/release-automation/spec.md` | Modify (host/credential model) | ~6 |
| **Total** | | **~150** |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: pending
400-line budget risk: Low

### Suggested Work Units

| Unit | Goal | Likely PR | Focused test command | Runtime harness | Rollback boundary |
|---|---|---|---|---|---|
| 1 | Spec reconciliation (host/credential model) | PR 1 (single PR) | Read diff against `lab-devops`-confirmed env var names | — | `git revert` |
| 2 | `ci.yml` migrated to `pipelines` (4 jobs) + local `docker-build` with publish | PR 1 (same PR, separate commit) | Static read (no `${{ }}` in `run:` bodies, no `-p` on login, guard present, no `minikube` references, YAML-valid) | Throwaway branch push on `lab-runner` | `git revert` |
| 3 | `release.yml` migrated to `pipelines` (3 jobs) + local `release` job with publish, README | PR 1 (same PR, separate commit) | `gh release list` + Nexus UI check after a real `v*` tag | Real tag push against live Nexus | `git revert` |

## Phase 1: Spec Reconciliation

- [x] 1.1 Edit `specs/docker-image-publish/spec.md`: replace `NEXUS_DEPLOYER_USERNAME`/`NEXUS_DEPLOYER_PASSWORD` GitHub secrets language with `NEXUS_DOCKER_PUSH_USERNAME`/`NEXUS_DOCKER_PUSH_PASSWORD` ambient runner-pod env vars; replace `<minikube-ip>:30082` with `$NEXUS_REGISTRY_HOST` (`172.19.0.5:30083`, HTTPS); replace `self-hosted` runner label references with `lab-runner`.
- [x] 1.2 Edit `specs/release-automation/spec.md`: same host/credential-source replacements as 1.1.
- [x] 1.3 `specs/ci-pipeline/spec.md`: no change needed — already generic.

## Phase 2: `ci.yml`

- [x] 2.1 Replace `go-build-test`, `go-lint`, `hadolint`, `gitleaks` job bodies with `uses: robbasualto/pipelines/.github/workflows/<name>.yml@v1.0.1`, `with: { runner: lab-runner }`.
- [x] 2.2 `docker-build` stays a single local job, `needs: [go-build-test, go-lint, hadolint]`, `runs-on: lab-runner`.
- [x] 2.3 `docker-build`: compute `IMAGE="$NEXUS_REGISTRY_HOST/go-hadolint-poc:${GITHUB_SHA::7}"` inline via `$GITHUB_ENV` — fail loudly if `NEXUS_REGISTRY_HOST` is unset.
- [x] 2.4 `docker-build`: guard login/push/logout steps with `if: github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository`.
- [x] 2.5 `docker-build`: `docker login` using `$NEXUS_DOCKER_PUSH_USERNAME`/`$NEXUS_DOCKER_PUSH_PASSWORD`, `--password-stdin`, `::add-mask::` on the password.
- [x] 2.6 `docker-build`: `docker/build-push-action@v6` `tags: ${{ env.IMAGE }}`, `push: false`.
- [x] 2.7 `docker-build`: explicit `docker push "$IMAGE"` after smoke test + Trivy, guarded.
- [x] 2.8 `docker-build`: `docker logout "$NEXUS_REGISTRY_HOST"`, `if: always() && <guard>`.

## Phase 3: `release.yml`

- [x] 3.1 Replace `go-build-test`, `go-lint`, `hadolint` (no `gitleaks` in release) with `pipelines@v1.0.1` calls, `runner: lab-runner`.
- [x] 3.2 `release` stays a single local job, `needs: [go-build-test, go-lint, hadolint]`, `runs-on: lab-runner`, `permissions: contents: write`.
- [x] 3.3 `release`: compute `IMAGE="$NEXUS_REGISTRY_HOST/go-hadolint-poc:$GITHUB_REF_NAME"` inline — fail loudly if unset.
- [x] 3.4 `release`: build (`push:false`) → smoke test → login → push → logout (`if: always()`, no guard needed — tags cannot come from a fork) → `gh release create "$GITHUB_REF_NAME" --generate-notes`.

## Phase 4: Docs

- [x] 4.1 Create `README.md`: published image ref format (`172.19.0.5:30083/go-hadolint-poc:<tag>`), ambient env vars, accepted fork-PR/self-hosted-runner exposure note.

## Phase 5: Tests / Verification

- [x] 5.1 Static: read `ci.yml`/`release.yml` — no `${{ }}` inside any `run:` body, no `-p` on `docker login`, push step guarded and last, logout guarded with `always()`, zero `minikube` references, both YAML-parse-valid (`ruby -ryaml`).
- [ ] 5.2 Pipeline: throwaway branch push — verify `go-build-test`/`go-lint`/`hadolint`/`gitleaks` resolve correctly from `pipelines@v1.0.1`, `docker-build` builds/smoke-tests/scans/pushes a short-SHA image to `172.19.0.5:30083` (check Nexus UI).
- [ ] 5.3 Pipeline: force a gate failure (e.g. broken `gofmt`) — verify `docker-build` never starts (blocked by `needs:`), no new image.
- [ ] 5.4 Pipeline: fork-PR-shaped dry run — verify `docker-build` builds/smoke-tests/scans but login/push/logout show as skipped.
- [ ] 5.5 Pipeline: real `v*` tag push — verify image pushed to Nexus AND GitHub Release created, in that order.
- [ ] 5.6 Pipeline: scale `lab-devops`'s `stacks/nexus` deployment to 0, push a branch — verify push fails loudly, non-zero.

## Phase 6: Operational (not a code task)

- [x] 6.1 [Operational] Self-hosted runner already registered and verified — no manual registration needed.
