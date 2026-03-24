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
- Создаётся `.cursor/rules/<skill-name>.mdc` для каждого скилла
- `.cursor/rules/` добавляется в `.gitignore` целевого проекта автоматически
- Повторный запуск обновляет только изменившиеся файлы

## Структура .mdc файла

```yaml
---
description: Django model design patterns...   # из SKILL.md frontmatter
globs: ["**/models.py", "**/models/*.py"]       # из skill-rules.json → pathPatterns
alwaysApply: false
---

# Django Model Patterns
...                                             # тело SKILL.md
```

| Поле | Источник |
|------|----------|
| `description` | `SKILL.md` frontmatter (upstream) |
| `globs` | `.claude/hooks/skill-rules.json` → `skills.<name>.triggers.pathPatterns` (target) |
| `alwaysApply` | всегда `false` |
| Тело | `SKILL.md` body (upstream) |

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
