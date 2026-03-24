#!/usr/bin/env bash
# Синхронизирует .claude/ из этого upstream-репо в целевой проект.
#
# Использование:
#   bash scripts/sync-to-project.sh                          # показать статус
#   bash scripts/sync-to-project.sh --apply                  # применить
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
TARGET_DIR=""

# --- разбор аргументов ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --target) TARGET_DIR="$2"; shift 2 ;;
    *) echo "Неизвестный аргумент: $1" >&2; exit 1 ;;
  esac
done

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
  echo ""
  echo "Запусти с --apply чтобы применить:"
  echo "  bash scripts/sync-to-project.sh --apply"
  echo "  make sync-skills-apply"
else
  echo "Готово: новых=$NEW, обновлено=$UPDATED, защищённых=$SKIPPED"
  if [[ $((NEW + UPDATED)) -gt 0 ]]; then
    echo ""
    echo "Изменения применены в: $DST"
  fi
fi
