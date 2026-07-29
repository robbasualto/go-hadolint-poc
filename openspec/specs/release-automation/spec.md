# Release Automation Specification

## Purpose

Defines the tag-triggered release workflow for go-hadolint-poc: re-verifying quality gates on the tagged commit, proving the image is packageable, and creating a GitHub Release — without pushing to any registry or generating SBOM/signing artifacts (both explicitly deferred pending a registry decision).

## Requirements

### Requirement: Tag-Triggered Release Workflow

A tag push matching `v*` MUST trigger a release workflow (e.g. `.github/workflows/release.yml`) separate from `ci.yml`.

#### Scenario: Tag push triggers the workflow

- GIVEN a tag `v0.1.0` is pushed to the repository
- WHEN GitHub Actions evaluates triggers
- THEN the release workflow MUST start, and `ci.yml`'s jobs MUST NOT be the mechanism producing the release

#### Scenario: Non-matching ref does not trigger

- GIVEN a branch push or a tag not matching `v*`
- WHEN GitHub Actions evaluates triggers
- THEN the release workflow MUST NOT run

### Requirement: Independent Gate Re-Verification

The release workflow MUST re-run the build, vet, test, lint, format, and hadolint gates directly against the tagged commit. It MUST NOT assume or reuse the result of any prior `ci.yml` run for that commit, since a tag MAY point at a commit that skipped a pull request.

#### Scenario: Tagged commit passes all gates

- GIVEN a tagged commit with valid, lint-clean, formatted, hadolint-clean Go source
- WHEN the release workflow runs build, vet, test, lint, format, and hadolint steps
- THEN all steps MUST exit 0 before packaging proceeds

#### Scenario: Tagged commit was never covered by CI

- GIVEN a tag pushed directly against a commit that had no prior pull request or CI run
- WHEN the release workflow runs
- THEN it MUST execute all gates itself rather than skipping them for lack of a prior CI result

### Requirement: Image Build and Smoke Proof

The release workflow MUST build the Docker image from the tagged commit AND run the existing smoke test, asserting the container's stdout is exactly `Hello, world!`. A successful `docker build` alone MUST NOT be treated as sufficient proof of a releasable image.

#### Scenario: Image builds and smoke test passes

- GIVEN the tagged commit's Dockerfile builds successfully
- WHEN the release workflow runs the smoke-test container
- THEN stdout MUST equal exactly `Hello, world!` and this MUST be required before release creation

#### Scenario: Build succeeds but smoke test fails

- GIVEN the image builds but the container's stdout does not match `Hello, world!`
- WHEN the release workflow evaluates the smoke-test step
- THEN the workflow MUST fail and MUST NOT proceed to release creation

### Requirement: Conditional GitHub Release Creation

On all gates (build, vet, test, lint, format, hadolint, image build, smoke test) passing, the workflow MUST create a GitHub Release for the pushed tag with auto-generated release notes. It MUST NOT use changelog tooling or semantic-release. If any gate fails, the workflow MUST NOT create a GitHub Release; the tag remains in git, orphaned, and this is accepted behavior rather than a defect requiring remediation.

#### Scenario: All gates pass

- GIVEN every gate in the release workflow exits 0 for tag `v0.1.0`
- WHEN the final release step runs
- THEN a GitHub Release for `v0.1.0` MUST be created with auto-generated notes (no changelog tool, no semantic-release)

#### Scenario: A gate fails

- GIVEN any gate (e.g. `go vet`) fails for tag `v0.2.0`
- WHEN the release workflow reaches its final step
- THEN no GitHub Release MUST be created for `v0.2.0`, and the tag MUST remain in git unreleased with no automated retry or cleanup

### Requirement: No Registry Push

The release workflow MUST NOT push any container image to any container registry. Registry integration is explicitly deferred pending a not-yet-configured registry.

#### Scenario: Workflow makes no registry calls

- GIVEN the release workflow completes successfully for a passing tag
- WHEN its network activity is reviewed
- THEN it MUST show zero push operations to any container registry (e.g. GHCR, Docker Hub, or any other)

### Requirement: No SBOM or Image Signing

The release workflow MUST NOT generate a Software Bill of Materials (SBOM) and MUST NOT sign the built image. Both are explicitly deferred because they depend on a registry-resident image digest, which does not exist without a configured registry.

#### Scenario: No SBOM or signing steps run

- GIVEN a passing release workflow run
- WHEN its steps are inspected
- THEN no SBOM-generation step (e.g. Syft) and no image-signing step (e.g. cosign) MUST be present
