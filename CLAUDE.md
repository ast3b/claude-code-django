# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> This is a **template/configuration repository** — it contains Claude Code setup (skills, hooks, agents, workflows) for Django projects. There is no actual Django application code here. The directories `apps/`, `templates/`, `tests/`, etc. are referenced as conventions for target projects, not present in this repo.

## Quick Facts

- **Purpose**: Claude Code configuration template for Django + HTMX + PostgreSQL projects
- **Package Manager**: uv (for target projects)
- **Test Command**: `uv run pytest`
- **Lint Command**: `uv run ruff check .`
- **Format Command**: `uv run ruff format .`
- **Type Check**: `uv run pyright`

## Repository Structure

```
.claude/
├── settings.json          # Hooks, env vars, permissions
├── settings.md            # Human-readable hook docs
├── agents/
│   ├── code-reviewer.md   # Auto-triggered after code changes
│   └── github-workflow.md
├── hooks/
│   ├── skill-eval.sh      # Fires on every prompt (UserPromptSubmit)
│   ├── skill-eval.js      # Skill matching engine
│   └── skill-rules.json   # Keyword/path/intent rules for skill suggestions
└── skills/                # Domain knowledge skills (SKILL.md per skill)
.github/workflows/         # Scheduled and PR-triggered Claude Code workflows
.envrc                     # direnv config for worktree environment sharing
SKILLS.md                  # Full index of available skills with combinations
```

## Active Hooks (settings.json)

| Event | Trigger | Behavior |
|-------|---------|----------|
| `UserPromptSubmit` | Every prompt | Runs `skill-eval.sh` — suggests matching skills |
| `PreToolUse` (Edit/Write) | Any file edit | **Blocks edits on `main` branch** |
| `PostToolUse` (Edit/Write) | `.py` files | Auto-formats with `ruff format` |
| `PostToolUse` (Edit/Write) | `pyproject.toml`, `requirements*.txt` | Runs `uv sync` |
| `PostToolUse` (Edit/Write) | `test_*.py`, `*_test.py`, `*/tests/*.py` | Runs `pytest <file> -x -q` |
| `PostToolUse` (Edit/Write) | `.py` files | Type-checks with `pyright` (non-blocking) |
| `PostToolUse` (Edit/Write) | `.py` files | Lints with `ruff check` (non-blocking) |

## Git Conventions

- **Branch naming**: `{initials}/{description}` (e.g., `jd/fix-login`)
- **Commit format**: Conventional Commits (`feat:`, `fix:`, `docs:`, etc.)
- **PR titles**: Same as commit format

## Code Style (for target Django projects)

- Python 3.12+ with type hints required
- Ruff for linting and formatting
- pyright strict mode — no `Any` types
- Use early returns, avoid nested conditionals
- Prefer Function-Based Views
- Use `select_related()` / `prefetch_related()` to avoid N+1 queries

## Critical Rules (for target Django projects)

### Templates & HTMX
- Partial templates use `_partial.html` naming convention
- Handle `HX-Request` header for partial vs full page responses
- Always include `hx-indicator` for loading states

### Celery Tasks
- Tasks must be idempotent
- Pass serializable arguments only (no model instances)
- Use exponential backoff retry strategies

### Testing
- Write failing test first (TDD)
- Use Factory Boy: `UserFactory.create(is_admin=True)`
- Test behavior, not implementation

## Current Adaptation: e-rent/admin (venv)

This upstream repo has been adapted for a specific target project (`e-rent/admin`) that uses **pip + virtualenv** instead of `uv`. Forks should be aware of these intentional deviations:

| File | Default (uv) | This repo (venv) |
|------|-------------|-----------------|
| `skills/django-extensions/SKILL.md` | `uv run python manage.py` | `python manage.py` |
| `commands/fix.md` | `uv run pyright` | `ty check` |

The `CLAUDE.md` commands (this file) and `settings.json` hooks still document `uv run` as the **default template** — adapt them when forking.

---

## Forking & Customization

When using this as a base for your project, adapt these three files — they are **intentionally not overwritten** by the sync script:

### 1. `.claude/settings.json` — tool runner

Default uses `uv`. If your project uses pip + virtualenv, replace every `uv run X` with the direct venv path:

```json
// uv (default)
"command": "uv run ruff format \"$CLAUDE_TOOL_INPUT_FILE_PATH\""

// pip + venv
"command": "\"$CLAUDE_PROJECT_DIR\"/.venv/bin/ruff format \"$CLAUDE_TOOL_INPUT_FILE_PATH\""
```

Also adapt the dependency hook trigger (`pyproject.toml` → `requirements*.txt`) and the install command (`uv sync` → `pip install -r requirements.txt`).

### 2. `.claude/hooks/skill-rules.json` — directory mappings

Update `directoryMappings` and domain keywords to match your project structure:

```json
"directoryMappings": {
  "source/rent/": "django-models",
  "source/payment/": "django-models",
  "portal/": "htmx-patterns"
},
"skills": {
  "django-models": {
    "triggers": {
      "keywords": ["rental", "invoice", "your-domain-term"]
    }
  }
}
```

### 3. `.claude/rules/` — project-specific rules

Add `.md` files with a `paths:` frontmatter — Claude loads them automatically when working with matching files:

```markdown
---
paths:
  - "**/tests/**"
  - "**/payment/**"
---

# Testing rules for payment module
...
```

See `.claude/rules/core-testing.md` for a complete example.

---

## Skill Activation

See `SKILLS.md` for the full skill index with category tables and recommended combinations.

Before implementing ANY task, check if relevant skills apply:

- Debugging issues → `systematic-debugging` skill
- Exploring Django project (models, URLs, settings) → `django-extensions` skill
- Creating new skills → `skill-creator` skill
- Starting a new task → `onboard` skill
- Working a ticket → `ticket` skill
- Reviewing a PR → `pr-review` skill
- Summarizing branch changes → `pr-summary` skill
- Running quality checks → `code-quality` skill
- Checking docs accuracy → `docs-sync` skill
- Committing worktree changes and merging to master/main → `worktree-commit-merge` skill

## Working with Worktrees

```bash
claude --worktree   # Start Claude in isolated worktree branch
```

The `.envrc` (via direnv) automatically shares the main repo's `.venv` and `.env` with all worktrees — no need to reinstall dependencies per worktree.

When done in a worktree: say "commit and merge to main" → triggers `worktree-commit-merge` skill.

## Common Commands

```bash
# Development (target project)
uv run python manage.py runserver
uv run pytest
uv run pytest -x --lf                                      # Run last failed, stop on first failure
uv run pytest tests/path/test_foo.py::test_bar             # Run single test
uv run ruff check .
uv run ruff format .
uv run pyright

# Django
uv run python manage.py makemigrations
uv run python manage.py migrate
uv run python manage.py shell_plus                         # Enhanced shell (django-extensions)

# Celery
uv run celery -A config worker -l info
uv run celery -A config beat -l info

# Dependencies
uv sync
uv add <package>
uv add --dev <package>
```
