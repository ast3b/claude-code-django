# Интеграция с Cursor

Скиллы из этого репо можно автоматически конвертировать в [Cursor rules](https://docs.cursor.com/context/rules) (`.cursor/rules/*.mdc`) для целевого проекта.

Cursor получает те же доменные паттерны (django-models, htmx-patterns и т.д.), что и Claude Code — без ручной работы.

## Требования

- `python3` в PATH
- Целевой проект настроен через `.claude/hooks/skill-rules.json` (используется как источник `globs`)

## Подключение

```bash
# Из корня claude-code-django:
make sync-all-apply TARGET=/path/to/your-project
```

Что произойдёт:
- Создаётся `.cursor/rules/<skill-name>.mdc` для каждого скилла (description + globs из `skill-rules.json`)
- Создаётся `.cursor/rules/<rule-name>.mdc` для каждого `.claude/rules/*.md` в целевом проекте (description + globs из frontmatter `paths:`)
- `.cursor/rules/` добавляется в `.gitignore` целевого проекта автоматически
- Повторный запуск обновляет только изменившиеся файлы

## Структура .mdc файла

Два источника генерируют `.mdc` файлы:

**Скиллы** (upstream `.claude/skills/*/SKILL.md`):

| Поле | Источник |
|------|----------|
| `description` | `SKILL.md` frontmatter `description:` |
| `globs` | `.claude/hooks/skill-rules.json` → `skills.<name>.triggers.pathPatterns` (target) |
| `alwaysApply` | всегда `false` |
| Тело | `SKILL.md` body |

**Rules** (`.claude/rules/*.md` целевого проекта):

| Поле | Источник |
|------|----------|
| `description` | frontmatter `description:` rules-файла |
| `globs` | frontmatter `paths:` rules-файла (блочный YAML список) |
| `alwaysApply` | всегда `false` |
| Тело | тело rules-файла |

Upstream rules используют префикс `core-` (например, `core-testing.md`) чтобы избежать коллизии имён с проектными rules.

## Обновление

При обновлении скиллов из upstream — просто перезапустить:

```bash
make sync-all-apply TARGET=/path/to/your-project
```

Cursor rules будут пересозданы. `skill-rules.json` (источник globs) не перезаписывается.

## Команды

| Команда | Описание |
|---------|----------|
| `make sync-all TARGET=...` | Dry-run: показать что изменится |
| `make sync-all-apply TARGET=...` | Применить скиллы + Cursor rules |
| `make sync-skills-apply TARGET=...` | Только скиллы, без Cursor |

Флаги скрипта:

```bash
bash scripts/sync-to-project.sh --cursor --apply --target /path/to/project
bash scripts/sync-to-project.sh --no-cursor --apply --target /path/to/project
```

## Защита кастомных rules

Чтобы не перезаписывать собственные `.mdc` файлы в целевом проекте:

```bash
export CLAUDE_PROTECTED_CURSOR_RULES="my-custom-rule another-rule"
make sync-all-apply TARGET=/path/to/your-project
```

## .gitignore

`.cursor/rules/` автоматически добавляется в `.gitignore` целевого проекта при первом `sync-all-apply`. Файлы генерируются заново при каждом запуске и не должны коммититься.
