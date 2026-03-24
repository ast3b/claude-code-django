# Cursor Integration

Skills from this repo can be automatically converted into [Cursor rules](https://docs.cursor.com/context/rules) (`.cursor/rules/*.mdc`) for a target project.

Cursor gets the same domain patterns (django-models, htmx-patterns, etc.) as Claude Code — with no manual work.

## Requirements

- `python3` in PATH
- Target project configured with `.claude/hooks/skill-rules.json` (used as the source for `globs`)

## Setup

```bash
# From the claude-code-django root:
make sync-all-apply TARGET=/path/to/your-project
```

What happens:
- Creates `.cursor/rules/<skill-name>.mdc` for each skill (description + globs from `skill-rules.json`)
- Creates `.cursor/rules/<rule-name>.mdc` for each `.claude/rules/*.md` in the target project (description + globs from `paths:` frontmatter)
- Adds `.cursor/rules/` to the target project's `.gitignore` automatically
- Re-running only updates files that have changed

## .mdc file structure

Two sources generate `.mdc` files:

**Skills** (upstream `.claude/skills/*/SKILL.md`):

| Field | Source |
|-------|--------|
| `description` | `SKILL.md` frontmatter `description:` |
| `globs` | `.claude/hooks/skill-rules.json` → `skills.<name>.triggers.pathPatterns` (target) |
| `alwaysApply` | always `false` |
| Body | `SKILL.md` body |

**Rules** (target `.claude/rules/*.md`):

| Field | Source |
|-------|--------|
| `description` | rules file frontmatter `description:` |
| `globs` | rules file frontmatter `paths:` block list |
| `alwaysApply` | always `false` |
| Body | rules file body |

Upstream rules use the `core-` prefix (e.g., `core-testing.md`) to avoid name collision with project-specific rules.

## Updating

When upstream skills are updated, just re-run:

```bash
make sync-all-apply TARGET=/path/to/your-project
```

Cursor rules will be regenerated. `skill-rules.json` (globs source) is never overwritten.

## Commands

| Command | Description |
|---------|-------------|
| `make sync-all TARGET=...` | Dry run: show what would change |
| `make sync-all-apply TARGET=...` | Apply skills + Cursor rules |
| `make sync-skills-apply TARGET=...` | Skills only, no Cursor |

Script flags:

```bash
bash scripts/sync-to-project.sh --cursor --apply --target /path/to/project
bash scripts/sync-to-project.sh --no-cursor --apply --target /path/to/project
```

## Protecting custom rules

To prevent specific `.mdc` files in the target project from being overwritten:

```bash
export CLAUDE_PROTECTED_CURSOR_RULES="my-custom-rule another-rule"
make sync-all-apply TARGET=/path/to/your-project
```

## .gitignore

`.cursor/rules/` is automatically added to the target project's `.gitignore` on the first `sync-all-apply`. Generated files should not be committed — they are regenerated on every run.
