# Skill Registry — go-hadolint-poc

Detected: 2026-07-29

Scope: no project-level skill directories or convention files (`AGENTS.md`, `CLAUDE.md`, `.cursorrules`, etc.) exist in this repo. All entries below are user-level skills deduplicated by name across mirrored tool dirs (`~/.claude/skills` used as canonical path; identical copies also exist under `~/.config/opencode/skills`, `~/.copilot/skills`, `~/.codex/skills`, `~/.gemini/skills`). `sdd-*`, `_shared`, and `skill-registry` are excluded per scan rules (loaded directly by the SDD workflow instead).

## Skills Index

| Skill | Trigger | Path |
|---|---|---|
| go-testing | Go tests, go test coverage, Bubbletea teatest, golden files | `~/.claude/skills/go-testing/SKILL.md` |
| branch-pr | creating, opening, or preparing PRs for review | `~/.claude/skills/branch-pr/SKILL.md` |
| chained-pr | PRs over 400 lines, stacked PRs, review slices | `~/.claude/skills/chained-pr/SKILL.md` |
| work-unit-commits | implementation, commit splitting, chained PRs, keeping tests/docs with code | `~/.claude/skills/work-unit-commits/SKILL.md` |
| judgment-day | judgment day, dual review, adversarial review | `~/.claude/skills/judgment-day/SKILL.md` |
| comment-writer | PR feedback, issue replies, reviews, Slack messages, GitHub comments | `~/.claude/skills/comment-writer/SKILL.md` |
| issue-creation | creating GitHub issues, bug reports, feature requests | `~/.claude/skills/issue-creation/SKILL.md` |
| cognitive-doc-design | writing guides, READMEs, RFCs, onboarding, architecture, review-facing docs | `~/.claude/skills/cognitive-doc-design/SKILL.md` |
| skill-creator | new skills, agent instructions, documenting AI usage patterns | `~/.claude/skills/skill-creator/SKILL.md` |
| skill-improver | improve skills, audit skills, refactor skills, skill quality | `~/.claude/skills/skill-improver/SKILL.md` |

## Most Relevant to This Project

Given this is a Go proof-of-concept with no test files yet and a hadolint-checked Dockerfile in CI, the `go-testing` skill is the primary match for the "robust pipeline" goal (adding the first `*_test.go` files, coverage). `work-unit-commits` and `chained-pr` apply once implementation work begins to land as reviewable slices.

## Convention Files

None found (no `agents.md`, `AGENTS.md`, project `CLAUDE.md`, `.cursorrules`, `GEMINI.md`, or `copilot-instructions.md` in this repo).
