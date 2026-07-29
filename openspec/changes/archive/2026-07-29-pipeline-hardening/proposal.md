# Proposal: Pipeline Hardening (secrets scanning + registry-free release automation)

## Intent

The repo now has a public GitHub remote (`robbasualto/go-hadolint-poc`), so two POC-acceptable gaps now matter: **no secrets scanning** (CI proves the code builds, not that it is safe to publish) and **no release process** (0 tags, 0 releases — nothing marks "the version that was verified"). Neither gap needs a registry to close.

## Scope

### In Scope

- **`gitleaks` job** in `.github/workflows/ci.yml`: independent job (no `needs:`), reusing the existing `push`/`pull_request` triggers, `gitleaks/gitleaks-action` pinned to a current stable **v3.x.y** (v2 dies with Node 20 on 2026-09-16), `fetch-depth: 0` for full-history scanning.
- **`.github/workflows/release.yml`**, tag-triggered (`on: push: tags: ["v*"]`): re-runs build/test/lint/hadolint gates on the tagged commit, builds the Docker image **locally** (`docker build`, no push, no registry contact) to prove the tag is packageable, then creates a GitHub Release via `gh release create <tag> --generate-notes`.
- **`openspec/config.yaml`** `context` fix: "no remote" is stale.

### Out of Scope (deferred)

| Deferred | Reason |
|---|---|
| Registry push (GHCR or any) | User will deploy their own Nexus/OCI registry; not configured yet |
| SBOM generation (syft) | Requires a registry-resident image — deferred with the registry |
| Image signing (cosign) | Requires a registry-resident image digest — deferred with the registry |
| Multi-arch builds | Not selected |
| Coverage-threshold gating | Not selected |
| Branch-protection automation | Not selected; a repo setting, not a CI artifact |
| semantic-release / commitlint / changelog | No commit-convention history to retrofit; manual tag + auto-notes fits solo scale |

## Capabilities

### New Capabilities
- `release-automation`: tag-triggered verification, local image build, and GitHub Release creation.

### Modified Capabilities
- `ci-pipeline`: adds a mandatory secrets-scanning gate to the existing gate set.

## Approach

Exploration Approach 1, minus everything registry-dependent. Two additive, independent surfaces: one new CI job, one new workflow file. The existing 4 jobs and their triggers are untouched. Version choice stays human (`git tag vX.Y.Z`); the machine does verification, packaging proof, and release notes.

**No runtime dependency is added** — CI-only tooling; `go.mod` stays stdlib-only.

## Affected Areas

| Area | Impact | Description |
|---|---|---|
| `.github/workflows/ci.yml` | Modified | New independent `gitleaks` job |
| `.github/workflows/release.yml` | New | Tag-triggered verify + local build + GitHub Release |
| `openspec/specs/ci-pipeline/spec.md` | Modified (delta) | Secrets-scan requirement |
| `openspec/config.yaml` | Modified | Correct stale "no remote" context |
| `main.go`, `go.mod`, `Dockerfile` | Unchanged | No Go or image changes |

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| gitleaks flags historical secrets, blocking all PRs | Med | Triage on first run; rotate real leaks, `.gitleaksignore` false positives |
| `gh release create` needs `contents: write` | Med | Declare job `permissions: contents: write` explicitly |
| Default branch is `master`, not `main` | Low | No branch conditional is required in this scope; if one is added it MUST say `master` |
| Release workflow duplicates CI gate logic | Med | Accept duplication at this scale; reusable-workflow extraction is a later refinement |
| Scope creep back toward registry/SBOM/signing | Med | Explicitly deferred above; revisit only once Nexus is live |

## Rollback Plan

Both deliverables are additive and independently revertible:

- **gitleaks**: delete the job block from `ci.yml`; the other 4 jobs are unaffected (no `needs:` edge points at it).
- **release**: delete `.github/workflows/release.yml`; nothing references it. Existing Releases/tags survive and can be removed via `gh release delete` / `git push --delete origin <tag>`.
- **config**: revert the `openspec/config.yaml` hunk.

No data migration, no registry state, no secrets created, no Go code touched — `git revert` of the change commit fully restores the prior pipeline.

## Dependencies

- Public GitHub remote (already present).
- `gitleaks/gitleaks-action` v3.x.y must be resolved to a concrete released tag at apply time.
- `gh` CLI is preinstalled on GitHub-hosted runners; `GITHUB_TOKEN` with `contents: write` suffices — **no new secrets**.

## Success Criteria

- [ ] A PR containing a planted test credential fails CI on the `gitleaks` job.
- [ ] A clean PR passes `gitleaks` without changing the pass/fail behaviour of the existing 4 jobs.
- [ ] `gitleaks-action` is pinned to a v3.x.y tag, and checkout uses `fetch-depth: 0`.
- [ ] Pushing `v0.1.0` triggers `release.yml`, which runs the build/test/lint/hadolint gates and a local `docker build`.
- [ ] That run creates a GitHub Release for `v0.1.0` with auto-generated notes, and makes **zero** registry network calls.
- [ ] A tag whose commit fails any gate produces **no** GitHub Release.
- [ ] `go.mod` still declares zero dependencies.
- [ ] `openspec/config.yaml` `context` no longer says "no remote".
