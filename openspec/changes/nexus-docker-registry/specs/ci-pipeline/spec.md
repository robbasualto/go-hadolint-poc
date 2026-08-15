# Delta for CI Pipeline

## MODIFIED Requirements

### Requirement: Image Build and Smoke Test Gate

The CI pipeline MUST build the Docker image and MUST run a smoke-test container from it; the job MUST fail if either the build or the container run fails. On success, the job MUST authenticate to the Nexus Docker registry and push the image tagged with the short commit SHA before completing.
(Previously: image was built and smoke-tested but never pushed anywhere — `push: false`.)

#### Scenario: Image builds, runs, and pushes

- GIVEN a valid Dockerfile and application source
- WHEN the CI job builds the image, runs the smoke-test container, and both succeed
- THEN it MUST additionally authenticate to Nexus and push the SHA-tagged image before the job completes

#### Scenario: Build or smoke test fails, no push attempted

- GIVEN either the image build or the smoke-test container run fails
- WHEN the job evaluates whether to push
- THEN it MUST NOT attempt a push

## ADDED Requirements

### Requirement: Self-Hosted Runner for CI Jobs

Jobs in `ci.yml` triggered by `push` or `pull_request` MUST execute on the repository's registered self-hosted runner rather than a GitHub-hosted runner, so the runner has local network access to the Nexus Docker connector.

#### Scenario: docker-build job targets self-hosted runner

- GIVEN `ci.yml`'s `docker-build` job definition
- WHEN the workflow file is inspected
- THEN `runs-on` MUST reference the self-hosted runner label, not `ubuntu-latest` or another GitHub-hosted label
