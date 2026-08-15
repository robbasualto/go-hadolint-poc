# Docker Image Publish Specification

## Purpose

Defines how go-hadolint-poc pipelines authenticate to the Nexus Docker registry, name and tag published images, and push behavior/failure semantics for both branch/PR CI builds and tagged releases.

## Requirements

### Requirement: Registry Authentication

Every job that pushes an image MUST authenticate to the Nexus Docker registry via `docker login` using the `NEXUS_DEPLOYER_USERNAME` / `NEXUS_DEPLOYER_PASSWORD` GitHub Actions secrets before attempting a push; anonymous push MUST NOT be attempted.

#### Scenario: Login succeeds with valid deployer credentials

- GIVEN the `NEXUS_DEPLOYER_USERNAME`/`NEXUS_DEPLOYER_PASSWORD` secrets are configured and valid
- WHEN a job runs `docker login` against the registry host before pushing
- THEN the login MUST succeed and the subsequent push MUST proceed

#### Scenario: Login fails with invalid or missing credentials

- GIVEN the deployer secrets are missing, rotated, or invalid
- WHEN the job attempts `docker login`
- THEN the login step MUST fail non-zero and the job MUST stop before attempting a push

### Requirement: Registry-Qualified Image Naming

Every pushed image reference MUST be qualified as `<minikube-ip>:30082/go-hadolint-poc:<tag>`, where the host is the Minikube IP resolved at job runtime (not hardcoded) and the port is the Docker connector NodePort.

#### Scenario: Tag on a release build

- GIVEN a workflow run triggered by a `v*` tag push
- WHEN the release job builds and tags the image
- THEN `<tag>` MUST equal `github.ref_name` (e.g. `v0.1.0`)

#### Scenario: Tag on a branch/PR CI build

- GIVEN a workflow run triggered by `push` or `pull_request` on `ci.yml`
- WHEN the `docker-build` job builds and tags the image
- THEN `<tag>` MUST equal the short commit SHA of the build

### Requirement: Push Runs After Existing Gates

The image push MUST occur only after all pre-existing quality gates (build, vet, test, lint, format, hadolint, image build/smoke) have already passed for that job; a gate failure MUST prevent the push step from running.

#### Scenario: All gates pass, push proceeds

- GIVEN a CI or release run where every prior gate exits 0
- WHEN the workflow reaches the push step
- THEN the image MUST be pushed to the Nexus registry

#### Scenario: An earlier gate fails, push is skipped

- GIVEN any prior gate (e.g. `go vet`) fails
- WHEN the workflow evaluates subsequent steps
- THEN the push step MUST NOT run and no image reference MUST be published

### Requirement: Registry Unreachable Fails Loudly

If the Nexus registry is unreachable at push time (network error, connector down, DNS/IP resolution failure), the job MUST fail with a visible, non-zero exit rather than silently skipping the push or reporting success.

#### Scenario: Registry down during push

- GIVEN the Nexus Docker connector is unreachable when the push step runs
- WHEN `docker push` is attempted
- THEN the job MUST exit non-zero and the pipeline MUST report failure, with the connector error visible in the job log

### Requirement: Self-Hosted Runner Execution

Both `ci.yml` (`push` and `pull_request` triggers) and `release.yml` (`v*` tag trigger) jobs that build and push images MUST run on the self-hosted runner registered to this repository, co-located with the Minikube/Nexus host, rather than a GitHub-hosted runner.

#### Scenario: CI job runs on self-hosted runner

- GIVEN a `push` or `pull_request` event triggers `ci.yml`
- WHEN the `docker-build` job (or equivalent) executes
- THEN it MUST run on `runs-on: self-hosted`, not a GitHub-hosted runner label

#### Scenario: Release job runs on self-hosted runner

- GIVEN a `v*` tag push triggers `release.yml`
- WHEN the release job executes
- THEN it MUST run on `runs-on: self-hosted`
