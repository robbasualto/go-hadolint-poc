# App Greeting Specification

## Purpose

Defines the testable core behavior of the greeting program: a pure function separated from its side-effecting print call, unit-tested, staying in `package main`.

## Requirements

### Requirement: Pure Greeting Function

The program MUST expose a pure function (e.g. `greeting() string`) that returns the greeting text with no side effects (no printing, no I/O).

#### Scenario: Function returns expected text

- GIVEN the `greeting()` function is called
- WHEN its return value is inspected
- THEN it MUST equal the exact expected greeting string
- AND the call MUST produce no stdout/stderr output

### Requirement: Main Prints the Pure Value

`main()` MUST print the value returned by `greeting()`, and MUST NOT contain the greeting text as an inline literal separate from that function.

#### Scenario: Program output matches function output

- GIVEN the compiled binary is executed
- WHEN it runs to completion
- THEN stdout MUST equal `greeting()` followed by a newline

### Requirement: Unit Test Coverage

`greeting()` MUST have at least one passing automated unit test in `main_test.go`, satisfying the repository's `strict_tdd: true` convention as the first test in the repo.

#### Scenario: Test passes

- GIVEN `main_test.go` defines a test calling `greeting()`
- WHEN `go test ./...` runs
- THEN the test MUST pass and assert the exact expected string

#### Scenario: Function stays in package main

- GIVEN the extraction of `greeting()` from `main()`
- WHEN the resulting code is reviewed
- THEN `greeting()` MUST remain declared in `package main`
- AND no new package or directory MUST be introduced for it
