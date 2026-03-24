#!/usr/bin/env bash
# Синхронизирует .claude/ из этого upstream-репо в целевой проект.
#
# Использование:
#   bash scripts/sync-to-project.sh                          # показать статус
#   bash scripts/sync-to-project.sh --apply                  # применить
#   bash scripts/sync-to-project.sh --cursor                 # статус + Cursor rules
#   bash scripts/sync-to-project.sh --apply --cursor         # применить + Cursor rules
#   bash scripts/sync-to-project.sh --target /path/to/proj   # указать цель явно
#   bash scripts/sync-to-project.sh --apply --target /path/to/proj
#
# Целевой проект определяется (в порядке приоритета):
#   1. --target <path>
#   2. Переменная окружения CLAUDE_SYNC_TARGET
#   3. Файл .sync-target в корне этого репо
#
# Файлы, которые НИКОГДА не перезаписываются в целевом проекте:
#   .claude/settings.json          — содержит project-specific пути инструментов
#   .claude/hooks/skill-rules.json — содержит project-specific директории и ключевые слова

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPLY=0
CURSOR=0
TARGET_DIR=""

# Защищённые Cursor rules (не перезаписываются и не удаляются)
# Настраивается через CLAUDE_PROTECTED_CURSOR_RULES="rule1 rule2"
PROTECTED_CURSOR=(${CLAUDE_PROTECTED_CURSOR_RULES:-})

# --- разбор аргументов ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)     APPLY=1; shift ;;
    --cursor)    CURSOR=1; shift ;;
    --no-cursor) CURSOR=0; shift ;;
    --target)    TARGET_DIR="$2"; shift 2 ;;
    *) echo "Неизвестный аргумент: $1" >&2; exit 1 ;;
  esac
done

# --- preflight check: python3 нужен для генерации Cursor rules ---
CURSOR_ENABLED=1
if ! command -v python3 &>/dev/null; then
  echo "WARN: python3 не найден — Cursor rules не будут сгенерированы" >&2
  CURSOR_ENABLED=0
fi

# --- определение целевого проекта ---
if [[ -z "$TARGET_DIR" ]]; then
  TARGET_DIR="${CLAUDE_SYNC_TARGET:-}"
fi
if [[ -z "$TARGET_DIR" && -f "$REPO_ROOT/.sync-target" ]]; then
  TARGET_DIR="$(cat "$REPO_ROOT/.sync-target" | tr -d '[:space:]')"
fi
if [[ -z "$TARGET_DIR" ]]; then
  echo "Ошибка: целевой проект не указан." >&2
  echo "" >&2
  echo "Укажи цель одним из способов:" >&2
  echo "  1. bash scripts/sync-to-project.sh --target /path/to/project" >&2
  echo "  2. export CLAUDE_SYNC_TARGET=/path/to/project" >&2
  echo "  3. echo '/path/to/project' > .sync-target" >&2
  exit 1
fi

TARGET_DIR="$(realpath "$TARGET_DIR")"

if [[ ! -d "$TARGET_DIR" ]]; then
  echo "Ошибка: директория не найдена: $TARGET_DIR" >&2
  exit 1
fi

SRC="$REPO_ROOT/.claude"
DST="$TARGET_DIR/.claude"

# --- файлы, которые никогда не перезаписываются ---
PROTECTED=(
  "settings.json"
  "hooks/skill-rules.json"
)

echo "==> Upstream:  $REPO_ROOT"
echo "==> Target:    $TARGET_DIR"
echo ""

# Проверяем, есть ли .claude/ в целевом проекте
if [[ ! -d "$DST" ]]; then
  if [[ $APPLY -eq 0 ]]; then
    echo "В целевом проекте нет .claude/ — будет создана при --apply."
  else
    mkdir -p "$DST"
    echo "Создана директория $DST"
  fi
fi

UPDATED=0
SKIPPED=0
NEW=0

# --- синхронизируемые поддиректории ---
SYNC_DIRS=(
  "skills"
  "rules"
  "agents"
  "commands"
)

# --- синхронизируемые файлы из hooks/ (кроме защищённых) ---
SYNC_HOOK_FILES=(
  "hooks/skill-eval.sh"
  "hooks/skill-eval.js"
  "hooks/skill-rules.schema.json"
  "hooks/skill-eval-prompt.md"
)

is_protected() {
  local rel="$1"
  for p in "${PROTECTED[@]}"; do
    [[ "$rel" == "$p" ]] && return 0
  done
  return 1
}

sync_file() {
  local rel="$1"   # относительный путь внутри .claude/
  local src="$SRC/$rel"
  local dst="$DST/$rel"

  [[ ! -f "$src" ]] && return 0

  if is_protected "$rel"; then
    echo "  PROTECTED (skip): $rel"
    SKIPPED=$((SKIPPED + 1))
    return 0
  fi

  if [[ ! -f "$dst" ]]; then
    echo "  NEW: $rel"
    if [[ $APPLY -eq 1 ]]; then
      mkdir -p "$(dirname "$dst")"
      cp "$src" "$dst"
    fi
    NEW=$((NEW + 1))
  elif diff -q "$src" "$dst" > /dev/null 2>&1; then
    echo "  OK (no changes): $rel"
  else
    echo "  UPDATE: $rel"
    if [[ $APPLY -eq 1 ]]; then
      cp "$src" "$dst"
    fi
    UPDATED=$((UPDATED + 1))
  fi
}

sync_dir() {
  local dir="$1"   # поддиректория внутри .claude/
  local src_dir="$SRC/$dir"

  [[ ! -d "$src_dir" ]] && return 0

  while IFS= read -r -d '' src_file; do
    local rel="${dir}/${src_file#$src_dir/}"
    # для директорий с вложенными файлами
    rel="${src_file#$SRC/}"
    sync_file "$rel"
  done < <(find "$src_dir" -type f -print0)
}

sync_cursor_rules() {
  local target="$1"
  [[ $APPLY -eq 1 ]] && mkdir -p "$target/.cursor/rules"

  local cursor_updated=0 cursor_new=0 cursor_skipped=0

  echo "--- Cursor rules ---"

  # --- генерация .mdc для каждого скилла ---
  for skill_dir in "$REPO_ROOT/.claude/skills"/*/; do
    local name
    name=$(basename "$skill_dir")
    local skill_md="$skill_dir/SKILL.md"
    [[ ! -f "$skill_md" ]] && continue

    # Проверка защищённых
    local skip=0
    for p in "${PROTECTED_CURSOR[@]:-}"; do
      [[ "$name" == "$p" ]] && skip=1 && break
    done
    if [[ $skip -eq 1 ]]; then
      echo "  PROTECTED (cursor): $name"
      cursor_skipped=$((cursor_skipped+1))
      continue
    fi

    # description из SKILL.md frontmatter
    local desc
    desc=$(python3 "$REPO_ROOT/scripts/parse_skill_meta.py" "$skill_md" description 2>/dev/null) \
      || { echo "  WARN: не удалось прочитать $skill_md" >&2; continue; }
    [[ -z "$desc" ]] && desc="$name"

    # globs из TARGET skill-rules.json
    local rules_json="$target/.claude/hooks/skill-rules.json"
    local globs="[]"
    if [[ -f "$rules_json" ]]; then
      globs=$(python3 "$REPO_ROOT/scripts/parse_skill_meta.py" "$rules_json" "globs:$name" 2>/dev/null) \
        || globs="[]"
    else
      echo "  WARN: skill-rules.json не найден в $target, globs будут пустыми" >&2
    fi

    # body SKILL.md (всё после второго ---)
    local body
    body=$(awk '/^---/{c++; next} c>=2{print}' "$skill_md")

    local dst="$target/.cursor/rules/$name.mdc"
    local content
    content=$(printf -- '---\ndescription: %s\nglobs: %s\nalwaysApply: false\n---\n%s' \
      "$desc" "$globs" "$body")

    if [[ ! -f "$dst" ]]; then
      echo "  NEW (cursor): $name.mdc"
      [[ $APPLY -eq 1 ]] && printf '%s\n' "$content" > "$dst"
      cursor_new=$((cursor_new+1))
    elif [[ "$(cat "$dst")" != "$content" ]]; then
      echo "  UPDATE (cursor): $name.mdc"
      [[ $APPLY -eq 1 ]] && printf '%s\n' "$content" > "$dst"
      cursor_updated=$((cursor_updated+1))
    else
      echo "  OK (cursor): $name.mdc"
    fi
  done

  # --- очистка устаревших .mdc ---
  if [[ -d "$target/.cursor/rules" ]]; then
    for mdc_file in "$target/.cursor/rules"/*.mdc; do
      [[ ! -f "$mdc_file" ]] && continue
      local mdc_name
      mdc_name=$(basename "$mdc_file" .mdc)
      local protected=0
      for p in "${PROTECTED_CURSOR[@]:-}"; do
        [[ "$mdc_name" == "$p" ]] && protected=1 && break
      done
      [[ $protected -eq 1 ]] && continue
      if [[ ! -d "$REPO_ROOT/.claude/skills/$mdc_name" ]]; then
        echo "  STALE (cursor): $mdc_name.mdc → удалено"
        [[ $APPLY -eq 1 ]] && rm -f "$mdc_file"
      fi
    done
  fi

  echo ""
  echo "Cursor rules: новых=$cursor_new, обновлено=$cursor_updated, защищённых=$cursor_skipped"

  # Убедиться что .cursor/rules/ в .gitignore (файлы не зависят от ветки)
  local gitignore="$target/.gitignore"
  local entry=".cursor/rules/"
  if ! grep -qxF "$entry" "$gitignore" 2>/dev/null; then
    printf '\n# Cursor rules (auto-generated, do not commit)\n%s\n' "$entry" >> "$gitignore"
    echo "  Added '$entry' to .gitignore"
  fi
}

# --- синхронизация директорий ---
for d in "${SYNC_DIRS[@]}"; do
  sync_dir "$d"
done

# --- синхронизация отдельных файлов из hooks/ ---
for f in "${SYNC_HOOK_FILES[@]}"; do
  sync_file "$f"
done

echo ""
if [[ $APPLY -eq 0 ]]; then
  echo "Статус: новых=$NEW, обновлений=$UPDATED, защищённых=$SKIPPED"
  if [[ $CURSOR -eq 1 && $CURSOR_ENABLED -eq 1 ]]; then
    echo ""
    sync_cursor_rules "$TARGET_DIR"
  fi
  echo ""
  echo "Запусти с --apply чтобы применить:"
  echo "  bash scripts/sync-to-project.sh --apply"
  echo "  make sync-skills-apply"
  if [[ $CURSOR -eq 0 ]]; then
    echo ""
    echo "Для генерации Cursor rules добавь --cursor:"
    echo "  make sync-all-apply"
  fi
else
  echo "Готово: новых=$NEW, обновлено=$UPDATED, защищённых=$SKIPPED"
  if [[ $((NEW + UPDATED)) -gt 0 ]]; then
    echo ""
    echo "Изменения применены в: $DST"
  fi
  if [[ $CURSOR -eq 1 && $CURSOR_ENABLED -eq 1 ]]; then
    echo ""
    sync_cursor_rules "$TARGET_DIR"
  fi
fi
