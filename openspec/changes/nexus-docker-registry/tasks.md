# Tasks: Nexus Docker Registry — `go-hadolint-poc` side (Phase B)

> Two `tasks.md`, one per repo, mirroring the existing per-repo spec/design split. Companion: `nexus-k8s/openspec/changes/nexus-docker-registry/tasks.md` (Phase A). **Blocked on Phase A**: do not merge/apply this repo's PR until Phase A has landed and been applied to the live Minikube cluster — the connector doesn't exist until then.

## Review Workload Forecast

Session review budget for this change: **800 changed lines** (overrides skill default 400).

| File | Action | Est. lines |
|---|---|---|
| `.github/workflows/ci.yml` | Modify | ~45-60 |
| `.github/workflows/release.yml` | Modify | ~30-40 |
| `README.md` | Create | ~40-60 |
| `specs/docker-image-publish/spec.md` | Modify (reconciliation) | ~4 |
| **Total** | | **~120-165** |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: pending
400-line budget risk: Low (against 800-line session budget: ~15-20%)

### Suggested Work Units

| Unit | Goal | Likely PR | Focused test command | Runtime harness | Rollback boundary |
|---|---|---|---|---|---|
| 1 | `ci.yml` runner + publish chain | PR 1 (single PR) | Static read of both workflows (no `${{ }}` in `run:` bodies, no `-p` on login, push last, guard present) | Throwaway branch push on the self-hosted runner | `git revert`: `push: false` + `ubuntu-latest` return |
| 2 | `release.yml` runner + publish chain, README | PR 1 (same PR, separate commits) | `gh release list` + Nexus UI check after a real `v*` tag | Real tag push against live Nexus | `git revert`; runner/secrets removed independently from repo settings |

## Phase 1: Spec Reconciliation

- [ ] 1.1 Edit `specs/docker-image-publish/spec.md` scenario "Login fails with invalid or missing credentials": add a precondition noting this scenario applies only to non-fork runs — the fork-PR publish guard (design Decision 5) skips the login step entirely on fork PRs.

## Phase 2: `ci.yml`

- [ ] 2.1 Set `runs-on: [self-hosted, minikube]` on `go-build-test`, `go-lint`, `hadolint`, `gitleaks` (steps unchanged).
- [ ] 2.2 Set `runs-on: [self-hosted, minikube]` on `docker-build`.
- [ ] 2.3 `docker-build`: add resolve-endpoint `run:` step (`minikube ip`), outputs `host`/`image`; fail loudly if empty.
- [ ] 2.4 `docker-build`: add publish guard `if: github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository` on resolve/login/push/logout steps.
- [ ] 2.5 `docker-build`: add `docker login` step — secrets via `env:`, `--password-stdin`, no `-p`.
- [ ] 2.6 `docker-build`: update `docker/build-push-action@v6` `tags:` to `$IMAGE` (short-SHA tag), keep `push: false`.
- [ ] 2.7 `docker-build`: add explicit `docker push "$IMAGE"` step after smoke test + Trivy.
- [ ] 2.8 `docker-build`: add `docker logout "$HOST"` with `if: always()`.

## Phase 3: `release.yml`

- [ ] 3.1 Set `runs-on: [self-hosted, minikube]` on the release job.
- [ ] 3.2 Insert resolve/login/tag/push chain (tag = `github.ref_name`) between smoke test and `gh release create`; no fork guard needed (tags cannot come from a fork).

## Phase 4: Docs

- [ ] 4.1 Create `README.md`: published image ref format, `insecure-registries` prerequisite for pulling, accepted fork-PR/self-hosted-runner exposure note.

## Phase 5: Tests / Verification

- [ ] 5.1 Static: read both workflows — no `${{ }}` inside any `run:` body, no `-p` on `docker login`, push step last, guard expression present.
- [ ] 5.2 Pipeline: throwaway branch push — verify short-SHA image published, all gates pass (check Nexus UI).
- [ ] 5.3 Pipeline: force a gate failure (e.g. broken `gofmt`) — verify push skipped, no new image.
- [ ] 5.4 Pipeline: fork-PR-shaped dry run — verify green with publish steps skipped.
- [ ] 5.5 Pipeline: real `v*` tag push — verify image pushed AND GitHub Release created.
- [ ] 5.6 Pipeline: scale Nexus deployment to 0, push a branch — verify push fails loudly, non-zero.

## Phase 6: Operational (not a code task)

- [ ] 6.1 [Operational] Register the self-hosted GitHub Actions runner for this repo with labels `self-hosted,minikube` (manual, one-time, GitHub UI token flow) per `nexus-k8s` runbook §9, before Phase 2/3 workflows can execute.
