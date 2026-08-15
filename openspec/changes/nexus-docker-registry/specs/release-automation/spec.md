# Delta for Release Automation

## MODIFIED Requirements

### Requirement: Image Build and Smoke Proof

The release workflow MUST build the Docker image from the tagged commit AND run the existing smoke test, asserting the container's stdout is exactly `Hello, world!`. A successful `docker build` alone MUST NOT be treated as sufficient proof of a releasable image. On success, the workflow MUST authenticate to the Nexus Docker registry and push the image tagged with `github.ref_name` before creating the GitHub Release.
(Previously: build+smoke proof was required but no push occurred; release creation followed smoke test directly.)

#### Scenario: Image builds and smoke test passes

- GIVEN the tagged commit's Dockerfile builds successfully
- WHEN the release workflow runs the smoke-test container
- THEN stdout MUST equal exactly `Hello, world!` and this MUST be required before push and release creation

#### Scenario: Build succeeds but smoke test fails

- GIVEN the image builds but the container's stdout does not match `Hello, world!`
- WHEN the release workflow evaluates the smoke-test step
- THEN the workflow MUST fail and MUST NOT proceed to push or release creation

#### Scenario: Push fails after a passing smoke test

- GIVEN the smoke test passes but the registry push fails (e.g. auth failure, registry unreachable)
- WHEN the release workflow evaluates the push step's result
- THEN the workflow MUST fail and MUST NOT create a GitHub Release for that tag

### Requirement: Registry Push on Release

On all gates (build, vet, test, lint, format, hadolint, image build, smoke test) passing, the release workflow MUST authenticate to the Nexus Docker registry using the `NEXUS_DEPLOYER_USERNAME`/`NEXUS_DEPLOYER_PASSWORD` secrets and push the image tagged `<minikube-ip>:30082/go-hadolint-poc:<github.ref_name>` before creating the GitHub Release.
(Previously: this behavior did not exist — the prior "No Registry Push" requirement forbade any registry push.)

#### Scenario: Successful push before release

- GIVEN all gates pass for tag `v0.1.0`
- WHEN the release workflow reaches the push step
- THEN the image MUST be pushed to the Nexus registry tagged `v0.1.0` before the GitHub Release step runs

#### Scenario: Anonymous or unauthenticated push is never attempted

- GIVEN the release job is about to push
- WHEN the push step executes
- THEN it MUST have already authenticated via `docker login` with the deployer credentials; it MUST NOT attempt an anonymous push

## REMOVED Requirements

### Requirement: No Registry Push

(Reason: the Nexus Docker registry is now provisioned and reachable; the deferred registry decision has been made, so pushing on release is now required behavior instead of forbidden.)
(Migration: replaced by the "Registry Push on Release" requirement above.)

## ADDED Requirements

### Requirement: Self-Hosted Runner for Release Job

The release workflow MUST execute on the repository's registered self-hosted runner rather than a GitHub-hosted runner, so it has local network access to the Nexus Docker connector.

#### Scenario: Release job targets self-hosted runner

- GIVEN `release.yml`'s job definition
- WHEN the workflow file is inspected
- THEN `runs-on` MUST reference the self-hosted runner label, not `ubuntu-latest` or another GitHub-hosted label
