# Exploration: pipeline-hardening (gitleaks, SBOM+signing, release automation)

## Current State

- `.github/workflows/ci.yml` has 4 jobs, triggered on every `push` and `pull_request` (no branch filter): `go-build-test`, `go-lint`, `hadolint`, and `docker-build` (needs all three). `docker-build` builds the image with `push: false` — the image only ever exists in the runner's local Docker daemon, tagged `go-hadolint-poc:ci`; it is never pushed to any registry today.
- Repo default branch is `master` (verified via GitHub API). 0 tags, 0 releases exist.
- `go.mod` is stdlib-only, zero dependencies. `Dockerfile` uses explicit `COPY main.go ./` (not `COPY . .`).
- The prior `robust-pipeline` change explicitly deferred all three of these items ("overkill for a no-deployment POC"). Revisited now because the repo has a real public GitHub remote.
- No `gitleaks`, `syft`/`cosign`, or release/tag workflow exists anywhere in the repo yet. No registry push exists.

## Affected Areas

- `.github/workflows/ci.yml` — new `gitleaks` job; `docker-build` job's push behavior needs a decision for SBOM+signing to be meaningful.
- New workflow file, e.g. `.github/workflows/release.yml` — tag-triggered job for release automation (build, push, SBOM, sign, GitHub Release).
- `openspec/specs/ci-pipeline/spec.md` — new requirements (secrets-scan gate, SBOM/signing gate, release gate) as deltas.
- `openspec/config.yaml` — `context` block still says "no remote"; stale regardless of this change, should be corrected.
- No Go source changes are implied by any of the 3 items (CI/supply-chain only).

## Findings Per Item

### 1. Secrets scanning (gitleaks)
- New independent job (no `needs:`), reusing existing `push`/`pull_request` triggers.
- Tool: `gitleaks/gitleaks-action`. v2 is being deprecated (Node 20 removal 2026-09-16); pin v3.x.y from the start.
- `fetch-depth: 0` on checkout to scan full history (cheap — only a few commits exist).

### 2. SBOM + image signing
- Tools: `anchore/sbom-action` (Syft) for SBOM; `sigstore/cosign-installer` + `cosign attest`/`cosign sign`.
- **Hard constraint**: cosign signs/attests a registry-resident image digest, not a local `docker build --load` tarball. Today's `docker-build` never pushes anywhere — SBOM+signing cannot work without a real registry push. This is an implicit prerequisite, not one of the 3 explicitly selected items, and needs explicit sign-off.
- Recommended registry: GHCR (`ghcr.io`) via built-in `GITHUB_TOKEN` (`permissions: packages: write`) — no new secret needed.
- Job placement: keep `docker-build` exactly as-is for PRs/every push (`push: false`, no registry contact). Add a separate job gated to `push` on `master` only that builds, pushes to GHCR, generates SBOM, signs/attests. Never push on PRs (registry/noise waste on branches that may never merge).

### 3. Release automation (semver + tags)
- 0 existing tags/releases, no enforced commit convention — a full `semantic-release`/`release-please` setup requires retrofitting commit discipline the repo has never had.
- Recommended: **manual `git tag vX.Y.Z`, automated packaging on tag push.** Tag-triggered workflow (`on: push: tags: ["v*"]`) builds, tags with semver, pushes to GHCR, runs SBOM+sign against the tagged image, creates a GitHub Release via `gh release create --generate-notes` (GitHub's native auto-notes — no changelog tooling). Human decides *when*/*what version*; machine does build/push/sign/release.

### 4. Signing identity
- **Keyless signing via GitHub OIDC (Fulcio/Rekor) is the right default**, not a manual key pair. Needs only `permissions: id-token: write` + `cosign-installer`. A manual keypair would require generating, storing as a secret, and rotating forever — real ongoing burden with no benefit for a solo repo with zero existing secrets. Composes cleanly with GHCR-via-`GITHUB_TOKEN` (no new secrets across all 3 items).

## Approaches

1. **Minimal/incremental hardening (recommended)** — gitleaks as an independent job on existing triggers; GHCR push + SBOM + keyless cosign signing scoped to `push` on `master` and tag events only (never PRs); release automation as manual-tag-triggers-automated-packaging, no commit-convention tooling.
   - Pros: zero new secrets anywhere; PR/existing `docker-build` experience unchanged; proportionate to solo POC; each item independently revertible.
   - Cons: registry push is a genuinely new capability not explicitly pre-approved; GHCR image eventually needs a retention/cleanup decision (not urgent now).
   - Effort: Medium.

2. **Comprehensive supply-chain automation** — push to GHCR on every push; full `semantic-release`/`release-please` with commitlint-enforced Conventional Commits and auto-changelog; sign every build, not just tagged releases.
   - Pros: closer to "production-grade" out of the box.
   - Cons: imposes commit-message discipline retroactively; pushes/signs on every branch (registry + Rekor noise); reintroduces the "overkill for a POC" judgment already made once.
   - Effort: High.

## Recommendation

Approach 1 was selected by the user. Delivers exactly the 3 selected items (secrets scanning, release automation), defers registry/SBOM/signing. Kept a consistent zero-secrets pattern, and treats release automation as automating the mechanical steps while keeping the human's version-bump decision.

## Risks

- Registry push to GHCR is an unstated-but-required prerequisite for SBOM+signing and release automation — must be surfaced explicitly, not silently added.
- Default branch is `master`, not `main` — any `if: github.ref == 'refs/heads/...'` condition must use the correct name.
- Scope-creep pressure toward full `semantic-release`/commitlint/changelog tooling — resist per the user's own prior "not overkill" framing.
- `gitleaks-action` v2 is being deprecated (Node 20 removal 2026-09-16) — pin v3 from the start.
- Pushing/signing on every PR (vs. restricting to `master` push + tags) creates disproportionate registry/Rekor-log noise for a solo repo.
- `openspec/config.yaml`'s `context` block still says "no remote" — stale, worth correcting in this change.

## Ready for Proposal

Yes. Approach 1 selected and implemented.
