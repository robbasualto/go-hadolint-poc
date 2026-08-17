# go-hadolint-poc

Minimal Go service used as a proof-of-concept CI/CD pipeline: build, test, lint,
Dockerfile lint (hadolint), secrets scan (gitleaks), image build + smoke test,
report-only vulnerability scan (Trivy), and image publish.

## Published image

Every green `push`/`pull_request` on `ci.yml` and every `v*` tag on `release.yml`
publishes the image to the lab's Nexus Docker registry:

```
172.19.0.5:30083/go-hadolint-poc:<tag>
```

- `<tag>` is the short commit SHA (`${GITHUB_SHA::7}`) on CI, or the tag name
  (`github.ref_name`, e.g. `v0.1.0`) on release.
- The connector is HTTPS with a self-signed certificate; the runner already
  trusts it, nothing to configure.

## Runner environment

CI and release jobs run on `lab-runner`, a self-hosted GitHub Actions runner
(ARC, `lab-devops`-managed) co-located with the Nexus registry. That runner
pod already provides, as environment variables, everything needed to publish —
**nothing needs to be configured in this repo's GitHub settings**:

| Variable | Purpose |
|---|---|
| `NEXUS_REGISTRY_HOST` | Registry host:port (`172.19.0.5:30083`) |
| `NEXUS_DOCKER_PUSH_USERNAME` | Push credential username |
| `NEXUS_DOCKER_PUSH_PASSWORD` | Push credential password |

These are provisioned outside this repo (Vault → External Secrets → the runner
pod's env) and are **not** GitHub Actions secrets.

## Accepted risk: fork-PR / self-hosted-runner exposure

The whole pipeline (not only the publish step) runs on `lab-runner`, including
`pull_request` events from forks. Because the credentials above are ambient
environment variables on the runner pod — not GitHub secrets withheld from
fork PRs — any job on that pod can read them, not just `docker-build`. The
publish steps (login, push, logout) are explicitly guarded to skip on
fork-originated PRs:

```
if: github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository
```

This guard is a trust boundary, not a credential-availability check: fork code
still builds, is smoke-tested, and is scanned — it just never gets to publish.
