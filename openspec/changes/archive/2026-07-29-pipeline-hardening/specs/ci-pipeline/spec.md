# Delta for CI Pipeline

## ADDED Requirements

### Requirement: Secrets Scanning Gate

The CI pipeline MUST run a `gitleaks` job on every `push` and `pull_request` event, using the same triggers as the existing build/lint/hadolint/docker-build jobs. The job MUST use `gitleaks/gitleaks-action` pinned to a stable `v3.x.y` release tag (not `v2`, which is deprecated ahead of GitHub-hosted runners dropping Node 20 on 2026-09-16). The checkout step MUST use `fetch-depth: 0` so the scan covers full git history, not just the latest commit. If the scan finds a genuine secret, the job MUST fail and MUST block the pipeline (this is a blocking gate, unlike the report-only Trivy scan).

#### Scenario: Clean history passes

- GIVEN a pull request or push with no secrets in the diff or prior git history
- WHEN the `gitleaks` job runs `gitleaks/gitleaks-action` (pinned `v3.x.y`) against a full-history checkout (`fetch-depth: 0`)
- THEN the job MUST exit 0 and MUST NOT affect the pass/fail status of the other four jobs

#### Scenario: A genuine secret is present

- GIVEN a pull request or push containing a real credential (e.g. a planted test API key) anywhere in the scanned history
- WHEN the `gitleaks` job runs
- THEN the job MUST exit non-zero and the pipeline MUST report failure, blocking merge

#### Scenario: v2 action is not used

- GIVEN the `gitleaks` job definition in `.github/workflows/ci.yml`
- WHEN the workflow file is inspected
- THEN `gitleaks/gitleaks-action` MUST be pinned to a `v3.x.y` tag, and MUST NOT reference `v2` or an unpinned/floating tag
