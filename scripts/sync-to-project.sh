#!/usr/bin/env bash
# Syncs .claude/ from this upstream repo into a target project.
#
# Usage:
#   bash scripts/sync-to-project.sh                          # show status (dry run)
#   bash scripts/sync-to-project.sh --apply                  # apply changes
#   bash scripts/sync-to-project.sh --cursor                 # dry run + Cursor rules
#   bash scripts/sync-to-project.sh --apply --cursor         # apply + Cursor rules
#   bash scripts/sync-to-project.sh --target /path/to/proj   # specify target explicitly
#   bash scripts/sync-to-project.sh --apply --target /path/to/proj
#
# Target project resolution (in order of priority):
#   1. --target <path>
#   2. CLAUDE_SYNC_TARGET environment variable
#   3. .sync-target file in the repo root
#
# Files that are NEVER overwritten in the target project:
#   .claude/settings.json          — contains project-specific tool paths
#   .claude/hooks/skill-rules.json — contains project-specific directories and keywords

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPLY=0
CURSOR=0
TARGET_DIR=""

# Protected Cursor rules (never overwritten or deleted)
# Configure via: CLAUDE_PROTECTED_CURSOR_RULES="rule1 rule2"
PROTECTED_CURSOR=(${CLAUDE_PROTECTED_CURSOR_RULES:-})

# --- argument parsing ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)     APPLY=1; shift ;;
    --cursor)    CURSOR=1; shift ;;
    --no-cursor) CURSOR=0; shift ;;
    --target)    TARGET_DIR="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# --- preflight check: python3 is required for Cursor rules generation ---
CURSOR_ENABLED=1
if ! command -v python3 &>/dev/null; then
  echo "WARN: python3 not found — Cursor rules will not be generated" >&2
  CURSOR_ENABLED=0
fi

# --- resolve target project ---
if [[ -z "$TARGET_DIR" ]]; then
  TARGET_DIR="${CLAUDE_SYNC_TARGET:-}"
fi
if [[ -z "$TARGET_DIR" && -f "$REPO_ROOT/.sync-target" ]]; then
  TARGET_DIR="$(cat "$REPO_ROOT/.sync-target" | tr -d '[:space:]')"
fi
if [[ -z "$TARGET_DIR" ]]; then
  echo "Error: target project not specified." >&2
  echo "" >&2
  echo "Specify the target in one of these ways:" >&2
  echo "  1. bash scripts/sync-to-project.sh --target /path/to/project" >&2
  echo "  2. export CLAUDE_SYNC_TARGET=/path/to/project" >&2
  echo "  3. echo '/path/to/project' > .sync-target" >&2
  exit 1
fi

TARGET_DIR="$(realpath "$TARGET_DIR")"

if [[ ! -d "$TARGET_DIR" ]]; then
  echo "Error: directory not found: $TARGET_DIR" >&2
  exit 1
fi

SRC="$REPO_ROOT/.claude"
DST="$TARGET_DIR/.claude"

# --- files that are never overwritten ---
PROTECTED=(
  "settings.json"
  "hooks/skill-rules.json"
)

echo "==> Upstream:  $REPO_ROOT"
echo "==> Target:    $TARGET_DIR"
echo ""

# Check if .claude/ exists in the target project
if [[ ! -d "$DST" ]]; then
  if [[ $APPLY -eq 0 ]]; then
    echo "Target has no .claude/ directory — will be created with --apply."
  else
    mkdir -p "$DST"
    echo "Created directory $DST"
  fi
fi

UPDATED=0
SKIPPED=0
NEW=0

# --- directories to sync ---
SYNC_DIRS=(
  "skills"
  "rules"
  "agents"
  "commands"
)

# --- individual hook files to sync (excluding protected) ---
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
  local rel="$1"   # relative path inside .claude/
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
  local dir="$1"   # subdirectory inside .claude/
  local src_dir="$SRC/$dir"

  [[ ! -d "$src_dir" ]] && return 0

  while IFS= read -r -d '' src_file; do
    local rel="${dir}/${src_file#$src_dir/}"
    # handle nested directories
    rel="${src_file#$SRC/}"
    sync_file "$rel"
  done < <(find "$src_dir" -type f -print0)
}

sync_cursor_rules() {
  local target="$1"
  [[ $APPLY -eq 1 ]] && mkdir -p "$target/.cursor/rules"

  local cursor_updated=0 cursor_new=0 cursor_skipped=0

  echo "--- Cursor rules ---"

  # --- generate .mdc for each skill ---
  for skill_dir in "$REPO_ROOT/.claude/skills"/*/; do
    local name
    name=$(basename "$skill_dir")
    local skill_md="$skill_dir/SKILL.md"
    [[ ! -f "$skill_md" ]] && continue

    # check protected list
    local skip=0
    for p in "${PROTECTED_CURSOR[@]:-}"; do
      [[ "$name" == "$p" ]] && skip=1 && break
    done
    if [[ $skip -eq 1 ]]; then
      echo "  PROTECTED (cursor): $name"
      cursor_skipped=$((cursor_skipped+1))
      continue
    fi

    # description from SKILL.md frontmatter
    local desc
    desc=$(python3 "$REPO_ROOT/scripts/parse_skill_meta.py" "$skill_md" description 2>/dev/null) \
      || { echo "  WARN: could not read $skill_md" >&2; continue; }
    [[ -z "$desc" ]] && desc="$name"

    # globs from TARGET skill-rules.json
    local rules_json="$target/.claude/hooks/skill-rules.json"
    local globs="[]"
    if [[ -f "$rules_json" ]]; then
      globs=$(python3 "$REPO_ROOT/scripts/parse_skill_meta.py" "$rules_json" "globs:$name" 2>/dev/null) \
        || globs="[]"
    else
      echo "  WARN: skill-rules.json not found in $target, globs will be empty" >&2
    fi

    # SKILL.md body (everything after the second ---)
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

  # --- generate .mdc for each rules file in target ---
  for rule_md in "$target/.claude/rules"/*.md; do
    [[ ! -f "$rule_md" ]] && continue
    local name
    name=$(basename "$rule_md" .md)

    local skip=0
    for p in "${PROTECTED_CURSOR[@]:-}"; do
      [[ "$name" == "$p" ]] && skip=1 && break
    done
    if [[ $skip -eq 1 ]]; then
      echo "  PROTECTED (cursor/rule): $name"
      cursor_skipped=$((cursor_skipped+1))
      continue
    fi

    local desc
    desc=$(python3 "$REPO_ROOT/scripts/parse_skill_meta.py" "$rule_md" description 2>/dev/null) \
      || { echo "  WARN: could not read $rule_md" >&2; continue; }
    [[ -z "$desc" ]] && desc="$name"

    local globs
    globs=$(python3 "$REPO_ROOT/scripts/parse_skill_meta.py" "$rule_md" paths 2>/dev/null) \
      || globs="[]"

    local body
    body=$(awk '/^---/{c++; next} c>=2{print}' "$rule_md")

    local dst="$target/.cursor/rules/$name.mdc"
    local content
    content=$(printf -- '---\ndescription: %s\nglobs: %s\nalwaysApply: false\n---\n%s' \
      "$desc" "$globs" "$body")

    if [[ ! -f "$dst" ]]; then
      echo "  NEW (cursor/rule): $name.mdc"
      [[ $APPLY -eq 1 ]] && printf '%s\n' "$content" > "$dst"
      cursor_new=$((cursor_new+1))
    elif [[ "$(cat "$dst")" != "$content" ]]; then
      echo "  UPDATE (cursor/rule): $name.mdc"
      [[ $APPLY -eq 1 ]] && printf '%s\n' "$content" > "$dst"
      cursor_updated=$((cursor_updated+1))
    else
      echo "  OK (cursor/rule): $name.mdc"
    fi
  done

  # --- remove stale .mdc files ---
  if [[ -d "$target/.cursor/rules" ]]; then
    # Build set of valid names from both skills and rules
    declare -A valid_mdc_names
    for _sd in "$REPO_ROOT/.claude/skills"/*/; do
      [[ -d "$_sd" ]] && valid_mdc_names[$(basename "$_sd")]=1
    done
    for _rm in "$target/.claude/rules"/*.md; do
      [[ -f "$_rm" ]] && valid_mdc_names[$(basename "$_rm" .md)]=1
    done

    for mdc_file in "$target/.cursor/rules"/*.mdc; do
      [[ ! -f "$mdc_file" ]] && continue
      local mdc_name
      mdc_name=$(basename "$mdc_file" .mdc)
      local protected=0
      for p in "${PROTECTED_CURSOR[@]:-}"; do
        [[ "$mdc_name" == "$p" ]] && protected=1 && break
      done
      [[ $protected -eq 1 ]] && continue
      if [[ -z "${valid_mdc_names[$mdc_name]+_}" ]]; then
        echo "  STALE (cursor): $mdc_name.mdc → removed"
        [[ $APPLY -eq 1 ]] && rm -f "$mdc_file"
      fi
    done
  fi

  echo ""
  echo "Cursor rules: new=$cursor_new, updated=$cursor_updated, protected=$cursor_skipped"

  # Ensure .cursor/rules/ is gitignored (files must be branch-independent)
  local gitignore="$target/.gitignore"
  local entry=".cursor/rules/"
  if ! grep -qxF "$entry" "$gitignore" 2>/dev/null; then
    printf '\n# Cursor rules (auto-generated, do not commit)\n%s\n' "$entry" >> "$gitignore"
    echo "  Added '$entry' to .gitignore"
  fi
}

# --- sync directories ---
for d in "${SYNC_DIRS[@]}"; do
  sync_dir "$d"
done

# --- sync individual hook files ---
for f in "${SYNC_HOOK_FILES[@]}"; do
  sync_file "$f"
done

echo ""
if [[ $APPLY -eq 0 ]]; then
  echo "Status: new=$NEW, updated=$UPDATED, protected=$SKIPPED"
  if [[ $CURSOR -eq 1 && $CURSOR_ENABLED -eq 1 ]]; then
    echo ""
    sync_cursor_rules "$TARGET_DIR"
  fi
  echo ""
  echo "Run with --apply to apply changes:"
  echo "  bash scripts/sync-to-project.sh --apply"
  echo "  make sync-skills-apply"
  if [[ $CURSOR -eq 0 ]]; then
    echo ""
    echo "Add --cursor to also generate Cursor rules:"
    echo "  make sync-all-apply"
  fi
else
  echo "Done: new=$NEW, updated=$UPDATED, protected=$SKIPPED"
  if [[ $((NEW + UPDATED)) -gt 0 ]]; then
    echo ""
    echo "Changes applied to: $DST"
  fi
  if [[ $CURSOR -eq 1 && $CURSOR_ENABLED -eq 1 ]]; then
    echo ""
    sync_cursor_rules "$TARGET_DIR"
  fi
fi
