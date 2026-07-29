# Archive Report: pipeline-hardening

**Change**: pipeline-hardening (secrets scanning + release automation)
**Project**: go-hadolint-poc
**Archived to**: `openspec/changes/archive/2026-07-29-pipeline-hardening/`
**Date**: 2026-07-29
**Status**: PASS (all requirements delivered, verified live against production repo)

## Executive Summary

Pipeline hardening change is complete and archived. Two additive workflow capabilities successfully delivered: (1) CI pipeline now includes mandatory secrets-scanning gate via `gitleaks` (2) tag-triggered release automation workflow created for packaging proof and GitHub Release creation. All 18/18 implementation and verification tasks complete. Live verification on `github.com/robbasualto/go-hadolint-poc` confirms: planted secrets blocked, clean runs pass, real release created with no registry calls. One real bug found and fixed during verification: `gitleaks-action@v3` requires explicit GITHUB_TOKEN env var for pull_request events. Delta specs successfully merged into main specs; ci-pipeline spec now contains 8 requirements (original 7 + Secrets Scanning Gate); release-automation spec created as new main spec.

## Artifacts Archive Contents

All artifacts successfully moved to archive location:

- [x] exploration.md — Market/scope/risk analysis completed
- [x] proposal.md — Scope and approach locked: secrets scanning + release automation (registry/SBOM/signing deferred)
- [x] design.md — Technical approach: gitleaks job in ci.yml, new release.yml workflow, inline gate duplication, threat matrix validated
- [x] tasks.md — 18 implementation & verification tasks: 18/18 complete (checked)
- [x] verify-report.md — Comprehensive verification: initial sandbox pass + complete Phase 5 live verification
- [x] specs/ci-pipeline/spec.md — Delta spec: Secrets Scanning Gate requirement (merged into main)
- [x] specs/release-automation/spec.md — New spec: 6 release automation requirements (created as main)

## Specs Merged into Main

### ci-pipeline Spec
- **Action**: Updated existing spec with delta
- **Prior state**: 7 requirements (build/vet, test, lint, format, hadolint, image build/smoke, report-only image scan)
- **Delta applied**: Added Requirement: Secrets Scanning Gate (with 3 scenarios: clean history passes, genuine secret blocked, v3 pinned)
- **Final state**: 8 requirements (original 7 + Secrets Scanning Gate)
- **Merge verified**: Delta requirement now present in `openspec/specs/ci-pipeline/spec.md` lines 110-131

### release-automation Spec
- **Action**: Created new main spec (no prior spec existed)
- **Requirements**: 6 requirements
  1. Tag-Triggered Release Workflow (`v*` push triggers separate workflow)
  2. Independent Gate Re-Verification (re-run all 6 gates on tagged commit)
  3. Image Build and Smoke Proof (docker build + smoke test validation)
  4. Conditional GitHub Release Creation (auto-notes, gated on all passes)
  5. No Registry Push (zero registry calls, `push: false` asserted)
  6. No SBOM or Image Signing (both deferred pending registry config)
- **Merge verified**: Spec created at `openspec/specs/release-automation/spec.md`

## Verification Summary

### Task Completion Gate

All 18 implementation and verification tasks marked complete in `tasks.md`:
- Phase 1 (RED): 4/4 tasks — version resolution & threat-matrix assertions
- Phase 2 (GREEN): 2/2 tasks — CI hardening (gitleaks job added)
- Phase 3 (GREEN): 6/6 tasks — release workflow (file created, gates duplicated, smoke test added, release step added, no registry/SBOM/signing)
- Phase 4: 1/1 task — config correction (openspec/config.yaml updated)
- Phase 5 (LIVE): 5/5 tasks — pipeline verification (all executed against live repo after merge)

No unchecked implementation tasks remain.

### Final Verdict from verify-report

**PASS** (upgraded from "PASS WITH WARNINGS" after Phase 5 completion)

Verify report date: 2026-07-29
- Static compliance: All spec requirements structurally compliant (YAML valid, actions pinned, no `continue-on-error`, threat matrix boundaries validated)
- Live verification (Phase 5): All 5 runtime tasks executed against production repo
  - 5.1 PASS: Planted secret blocked by gitleaks (after fixing real bug: missing GITHUB_TOKEN env var)
  - 5.2 PASS: Clean push to master passed all 5 jobs (gitleaks + 4 original)
  - 5.3 PASS: Tag v0.1.0 triggered release.yml, all gates passed, GitHub Release created
  - 5.4 PASS: Tag with failing gate produced no Release
  - 5.5 PASS: Zero registry calls confirmed across all runs

**Issues**: CRITICAL: None. WARNING: None (both initial warnings resolved with real evidence). SUGGESTION: Resolved (binary cleanup, .gitignore).

### Implementation Verification

Per launch prompt final-state facts:
- Verify report result: PASS (0 CRITICAL, 0 WARNING) ✓
- All 18/18 tasks complete including live verification ✓
- All work committed and pushed to master: commits cc4c97f, 4030130, 5ecbb2c, 1266b91 ✓
- Live verification evidence:
  - Planted-secret PR #1 correctly blocked by gitleaks ✓
  - gitleaks-action@v3 bug found and fixed (missing GITHUB_TOKEN for pull_request events) ✓
  - Clean push v0.1.0 created real GitHub Release ✓
  - Tag with intentional gate failure created no Release ✓
  - Zero registry calls confirmed ✓
- Related bug fix: golangci-lint-action@v9.3.0 invalid config-path input (fixed) ✓
- Throwaway artifacts cleaned (test PR, branches, tags) ✓

## Source of Truth Updated

Delta specs successfully merged into authoritative main specs:
- `openspec/specs/ci-pipeline/spec.md` — now contains 8 requirements (Secrets Scanning Gate added)
- `openspec/specs/release-automation/spec.md` — new main spec with 6 release automation requirements

Active change folder `openspec/changes/pipeline-hardening/` no longer contains live work; all content archived and final state recorded here.

## Dependencies and Risks

### No Unresolved Dependencies
- `gitleaks/gitleaks-action@v3.0.0` pinned to stable release (resolved at apply time via `gh api`)
- `GITHUB_TOKEN` (built-in runner secret, no new secrets provisioned)
- `gh` CLI (preinstalled on GitHub runners)
- Public GitHub remote already present

### Risks Cleared
- Registry push deferred (explicitly out-of-scope per proposal)
- SBOM/signing deferred (explicitly out-of-scope pending registry config)
- gitleaks action v2 deprecation: v3.0.0 pinned, avoiding Node 20 removal blocker
- Default branch `master` (not `main`): verified in all conditional logic
- No Go runtime dependencies added: `go.mod` remains stdlib-only

### Intentional Deferrals (Captured for Future Work)
- GHCR registry integration (user deploying own registry later)
- SBOM generation via syft (depends on registry-resident image)
- Image signing via cosign (depends on registry-resident image digest)
- semantic-release / commitlint / changelog tooling (no commit convention history; manual tag + auto-notes sufficient for POC scale)

## Change Properties

| Property | Value |
|---|---|
| Change type | CI/supply-chain (workflows + config) |
| Go code changed | No (workflows only) |
| Go tests added | No (no new Go code) |
| Runtime dependencies added | No (CI-only tooling) |
| Secrets created | No (GITHUB_TOKEN built-in) |
| Files created | 1 (`.github/workflows/release.yml`) |
| Files modified | 2 (`.github/workflows/ci.yml` + `openspec/config.yaml`) |
| Config updated | Yes (`openspec/config.yaml` context: "no remote" → remote URL + branch) |
| Rollback complexity | Low (deletable blocks, independent, no shared state) |

## Traceability

### OpenSpec Artifacts (Engram not used in prior phases)

All artifacts persisted to hybrid mode (filesystem + eventual Engram save):

- Artifact store location: `/home/jotaese/go-hadolint-poc/openspec/changes/archive/2026-07-29-pipeline-hardening/`
- Archive report saved: `archive-report.md` (this file)

### Repository State

- Master branch: `github.com/robbasualto/go-hadolint-poc`
- Work committed: YES (4 commits: cc4c97f, 4030130, 5ecbb2c, 1266b91)
- Release created: YES (v0.1.0 via release.yml)
- Test artifacts cleaned: YES (PR #1, branches, throwaway tag all deleted)

## SDD Cycle Complete

The pipeline-hardening change has been:
1. Explored (market, constraints, approaches analyzed)
2. Proposed (scope locked: secrets scanning + release automation)
3. Designed (threat matrix validated, file changes specified)
4. Tasked (18 tasks defined)
5. Applied (code written, tested, committed to master)
6. Verified (sandbox validation + live verification on production repo)
7. Archived (all artifacts moved, specs merged, final report recorded)

No unresolved issues. No outstanding dependencies. Ready for the next change.
