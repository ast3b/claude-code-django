# Claude Code Skills

This directory contains project-specific skills that provide Claude with domain knowledge and best practices for this Django codebase.

## Skills by Category

### Meta & Development Tools
| Skill | Description |
|-------|-------------|
| [skill-creator](.claude/skills/skill-creator/SKILL.md) | Guide for creating effective skills that extend Claude's capabilities |
| [django-extensions](.claude/skills/django-extensions/SKILL.md) | Django-extensions management commands for introspection, debugging, and development |

### Workflows
| Skill | Description |
|-------|-------------|
| [onboard](.claude/skills/onboard/SKILL.md) | Onboard Claude to a new task by exploring the codebase and building context |
| [ticket](.claude/skills/ticket/SKILL.md) | Work on a JIRA/Linear ticket end-to-end |
| [pr-review](.claude/skills/pr-review/SKILL.md) | Review a pull request using project standards |
| [pr-summary](.claude/skills/pr-summary/SKILL.md) | Generate a pull request summary for the current branch |
| [code-quality](.claude/skills/code-quality/SKILL.md) | Run code quality checks and report findings by severity |
| [docs-sync](.claude/skills/docs-sync/SKILL.md) | Check if documentation is in sync with code |
| [worktree-commit-merge](.claude/skills/worktree-commit-merge/SKILL.md) | Commit worktree changes, merge into master/main, sync branch |

### Testing & Debugging
| Skill | Description |
|-------|-------------|
| [pytest-django-patterns](.claude/skills/pytest-django-patterns/SKILL.md) | pytest-django, Factory Boy, fixtures, TDD workflow |
| [systematic-debugging](.claude/skills/systematic-debugging/SKILL.md) | Four-phase debugging methodology, root cause analysis |

### Django Core
| Skill | Description |
|-------|-------------|
| [django-models](.claude/skills/django-models/SKILL.md) | Model design, QuerySet optimization, signals, migrations |
| [django-forms](.claude/skills/django-forms/SKILL.md) | Form handling, validation, ModelForm patterns |
| [django-templates](.claude/skills/django-templates/SKILL.md) | Template inheritance, tags, filters, partials |

### Frontend & UI
| Skill | Description |
|-------|-------------|
| [htmx-patterns](.claude/skills/htmx-patterns/SKILL.md) | HTMX attributes, partial templates, dynamic UI |

### Background Tasks
| Skill | Description |
|-------|-------------|
| [celery-patterns](.claude/skills/celery-patterns/SKILL.md) | Celery tasks, retry strategies, periodic tasks |

---

## Skill Combinations for Common Tasks

### Building a New Feature
1. **django-models** - Design models
2. **django-forms** - Create forms for user input
3. **htmx-patterns** - Dynamic UI
4. **django-templates** - Page templates
5. **pytest-django-patterns** - Write tests (TDD)

### Building a Background Task
1. **celery-patterns** - Task definition
2. **django-models** - Database operations
3. **pytest-django-patterns** - Task tests

### Debugging an Issue
1. **systematic-debugging** - Root cause analysis
2. **pytest-django-patterns** - Write failing test first
3. **django-extensions** - Use show_urls, list_model_info, shell_plus for investigation

### Creating New Skills
1. **skill-creator** - Follow the skill creation guide
2. **django-extensions** - Test your skill with project introspection commands

---

## Adding New Skills

1. Create directory: `.claude/skills/skill-name/`
2. Add `SKILL.md` with YAML frontmatter:
   ```yaml
   ---
   name: skill-name
   description: What it does and when to use it. Include trigger keywords.
   ---
   ```
3. Add triggers to `.claude/hooks/skill-rules.json`
4. Update this file

**Important:** The `description` field is critical — Claude uses it to decide when to apply the skill.
