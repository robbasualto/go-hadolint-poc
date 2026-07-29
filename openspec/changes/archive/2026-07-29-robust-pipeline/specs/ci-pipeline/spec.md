# CI Pipeline Specification

## Purpose

Defines the required CI gates for go-hadolint-poc so the pipeline's green status is trustworthy: build, vet, test-with-coverage, lint, format, Dockerfile lint, image build/smoke, and report-only image scan.

## Requirements

### Requirement: Build and Vet Gate

The CI pipeline MUST run `go build ./...` and `go vet ./...`, and MUST fail if either command exits non-zero.

#### Scenario: Build succeeds, vet clean

- GIVEN a pull request with valid Go source
- WHEN the CI job runs `go build ./...` and `go vet ./...`
- THEN both commands MUST exit 0 and the job MUST pass

#### Scenario: Vet finds a suspicious construct

- GIVEN a change introducing a vet-flagged issue (e.g. bad Printf verb)
- WHEN `go vet ./...` runs
- THEN the job MUST exit non-zero and the pipeline MUST report failure

### Requirement: Test Execution Gate

The CI pipeline MUST invoke `go test ./... -cover` and MUST fail the build if any test fails. The job MUST NOT be considered a test gate unless it actually executes `go test`.

#### Scenario: All tests pass

- GIVEN `main_test.go` with passing table-driven tests
- WHEN the CI job runs `go test ./... -cover`
- THEN the job MUST exit 0 and coverage output MUST appear in the job log

#### Scenario: A test fails

- GIVEN a test asserting an incorrect expected value
- WHEN `go test ./... -cover` runs
- THEN the job MUST exit non-zero and the pipeline MUST report failure

### Requirement: Lint Gate

The CI pipeline MUST run `golangci-lint` at a pinned version against a checked-in `.golangci.yml` configuration, and MUST fail the build on any reported violation.

#### Scenario: No lint violations

- GIVEN source code compliant with `.golangci.yml`
- WHEN the pinned `golangci-lint` action runs
- THEN the job MUST pass

#### Scenario: A lint violation exists

- GIVEN source code violating an enabled linter rule
- WHEN `golangci-lint` runs
- THEN the job MUST exit non-zero and the pipeline MUST report failure

### Requirement: Format Gate

The CI pipeline MUST run `gofmt -l` across all Go source files and MUST fail the build if the command lists any file.

#### Scenario: All files formatted

- GIVEN all `.go` files are `gofmt`-clean
- WHEN `gofmt -l .` runs
- THEN the output MUST be empty and the job MUST pass

#### Scenario: An unformatted file exists

- GIVEN a `.go` file with non-canonical formatting
- WHEN `gofmt -l .` runs
- THEN the file path MUST appear in the output and the job MUST fail

### Requirement: Dockerfile Lint Gate

The CI pipeline MUST continue running `hadolint` against the Dockerfile and MUST fail the build on any hadolint violation.

#### Scenario: Dockerfile stays hadolint-clean

- GIVEN the existing multi-stage Dockerfile
- WHEN `hadolint` runs against it
- THEN the job MUST pass with zero findings

### Requirement: Image Build and Smoke Test Gate

The CI pipeline MUST build the Docker image and MUST run a smoke-test container from it; the job MUST fail if either the build or the container run fails.

#### Scenario: Image builds and runs

- GIVEN a valid Dockerfile and application source
- WHEN the CI job builds the image and runs the smoke-test container
- THEN both steps MUST succeed and the job MUST pass

### Requirement: Report-Only Image Scan

The CI pipeline SHOULD run a Trivy scan of the built image and SHOULD report findings in the job log, but the scan MUST NOT cause the pipeline to fail regardless of findings (`exit-code: 0`).

#### Scenario: Trivy finds vulnerabilities

- GIVEN a built image with known CVEs
- WHEN the Trivy scan step runs
- THEN findings MUST be visible in the job log
- AND the overall pipeline status MUST remain unaffected by the findings

#### Scenario: No coverage threshold enforced

- GIVEN `go test ./... -cover` reports a coverage percentage
- WHEN the CI job evaluates the result
- THEN the pipeline MUST NOT fail based on the coverage number (no threshold gate exists yet)
