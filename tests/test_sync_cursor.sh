#!/usr/bin/env bash
# Integration test for --cursor flag in sync-to-project.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/sync-to-project.sh"
PASS=0
FAIL=0

ok()   { echo "  OK: $*";   PASS=$((PASS+1)); }
fail() { echo "  FAIL: $*" >&2; FAIL=$((FAIL+1)); }

# --- Test 1: --cursor --apply creates .mdc files ---
TARGET=$(mktemp -d)
trap "rm -rf '$TARGET'" EXIT

mkdir -p "$TARGET/.claude/hooks"
cp "$REPO_ROOT/tests/fixtures/skill-rules.json" "$TARGET/.claude/hooks/"

bash "$SCRIPT" --cursor --apply --target "$TARGET" > /dev/null

MDC="$TARGET/.cursor/rules/django-models.mdc"
if [[ -f "$MDC" ]]; then
  ok "django-models.mdc created"
else
  fail "django-models.mdc not created"
fi

if grep -q "^description:" "$MDC" 2>/dev/null; then
  ok "description field present"
else
  fail "description field missing"
fi

if grep -q "^globs:" "$MDC" 2>/dev/null; then
  ok "globs field present"
else
  fail "globs field missing"
fi

if grep -q "^alwaysApply: false" "$MDC" 2>/dev/null; then
  ok "alwaysApply: false"
else
  fail "alwaysApply not set correctly"
fi

if grep -q '\*\*/models\.py' "$MDC" 2>/dev/null; then
  ok "pathPatterns from skill-rules.json in globs"
else
  fail "pathPatterns not found in globs"
fi

# --- Test 2: dry-run does NOT write files ---
TARGET2=$(mktemp -d)
trap "rm -rf '$TARGET' '$TARGET2'" EXIT

mkdir -p "$TARGET2/.claude/hooks"
cp "$REPO_ROOT/tests/fixtures/skill-rules.json" "$TARGET2/.claude/hooks/"

bash "$SCRIPT" --cursor --target "$TARGET2" > /dev/null

if [[ ! -f "$TARGET2/.cursor/rules/django-models.mdc" ]]; then
  ok "dry-run did not write files"
else
  fail "dry-run wrote files (should not)"
fi

# --- Test 3: without --cursor, no .cursor/rules created ---
TARGET3=$(mktemp -d)
trap "rm -rf '$TARGET' '$TARGET2' '$TARGET3'" EXIT

mkdir -p "$TARGET3/.claude/hooks"
cp "$REPO_ROOT/tests/fixtures/skill-rules.json" "$TARGET3/.claude/hooks/"

bash "$SCRIPT" --apply --target "$TARGET3" > /dev/null

if [[ ! -d "$TARGET3/.cursor" ]]; then
  ok "no --cursor flag → no .cursor/ dir"
else
  fail "no --cursor flag but .cursor/ was created"
fi

# --- Summary ---
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
