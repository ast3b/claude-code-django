#!/usr/bin/env bash
# Integration test for --cursor flag in sync-to-project.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/sync-to-project.sh"
PASS=0
FAIL=0

ok()   { echo "  OK: $*";   PASS=$((PASS+1)); }
fail() { echo "  FAIL: $*" >&2; FAIL=$((FAIL+1)); }

CLEANUP=()
trap 'rm -rf "${CLEANUP[@]}"' EXIT

# --- Test 1: --cursor --apply creates .mdc files ---
TARGET=$(mktemp -d); CLEANUP+=("$TARGET")

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
TARGET2=$(mktemp -d); CLEANUP+=("$TARGET2")

mkdir -p "$TARGET2/.claude/hooks"
cp "$REPO_ROOT/tests/fixtures/skill-rules.json" "$TARGET2/.claude/hooks/"

bash "$SCRIPT" --cursor --target "$TARGET2" > /dev/null

if [[ ! -f "$TARGET2/.cursor/rules/django-models.mdc" ]]; then
  ok "dry-run did not write files"
else
  fail "dry-run wrote files (should not)"
fi

# --- Test 3: without --cursor, no .cursor/rules created ---
TARGET3=$(mktemp -d); CLEANUP+=("$TARGET3")

mkdir -p "$TARGET3/.claude/hooks"
cp "$REPO_ROOT/tests/fixtures/skill-rules.json" "$TARGET3/.claude/hooks/"

bash "$SCRIPT" --apply --target "$TARGET3" > /dev/null

if [[ ! -d "$TARGET3/.cursor" ]]; then
  ok "no --cursor flag → no .cursor/ dir"
else
  fail "no --cursor flag but .cursor/ was created"
fi

# --- Test 4: rules/*.md → .mdc (globs from paths:, description from frontmatter) ---
TARGET4=$(mktemp -d); CLEANUP+=("$TARGET4")

mkdir -p "$TARGET4/.claude/hooks" "$TARGET4/.claude/rules"
cp "$REPO_ROOT/tests/fixtures/skill-rules.json" "$TARGET4/.claude/hooks/"

cat > "$TARGET4/.claude/rules/my-rule.md" << 'RULEEOF'
---
description: My custom rule
paths:
  - "**/models.py"
  - "**/models/**"
---

# My Rule

Some content here.
RULEEOF

bash "$SCRIPT" --cursor --apply --target "$TARGET4" > /dev/null

RULE_MDC="$TARGET4/.cursor/rules/my-rule.mdc"
if [[ -f "$RULE_MDC" ]]; then
  ok "rules file → my-rule.mdc created"
else
  fail "rules file → my-rule.mdc not created"
fi

if grep -q 'description: "My custom rule"' "$RULE_MDC" 2>/dev/null; then
  ok "rules .mdc: description from frontmatter"
else
  fail "rules .mdc: description not from frontmatter"
fi

if grep -q '\*\*/models\.py' "$RULE_MDC" 2>/dev/null; then
  ok "rules .mdc: globs from paths: frontmatter"
else
  fail "rules .mdc: globs not from paths: frontmatter"
fi

if grep -q "^alwaysApply: false" "$RULE_MDC" 2>/dev/null; then
  ok "rules .mdc: alwaysApply: false"
else
  fail "rules .mdc: alwaysApply not set"
fi

# --- Test 5: stale check does NOT delete rules-derived .mdc when rule exists ---
TARGET5=$(mktemp -d); CLEANUP+=("$TARGET5")

mkdir -p "$TARGET5/.claude/hooks" "$TARGET5/.claude/rules" "$TARGET5/.cursor/rules"
cp "$REPO_ROOT/tests/fixtures/skill-rules.json" "$TARGET5/.claude/hooks/"

# Create a rule file and a pre-existing matching .mdc
cat > "$TARGET5/.claude/rules/my-persistent-rule.md" << 'RULEEOF'
---
description: Persistent rule
paths:
  - "**/views.py"
---

# Persistent Rule
RULEEOF

# Pre-create the .mdc so we can check it's NOT deleted
echo "pre-existing" > "$TARGET5/.cursor/rules/my-persistent-rule.mdc"

bash "$SCRIPT" --cursor --apply --target "$TARGET5" > /dev/null

if [[ -f "$TARGET5/.cursor/rules/my-persistent-rule.mdc" ]]; then
  ok "stale check: rules-derived .mdc not deleted when rule file exists"
else
  fail "stale check: rules-derived .mdc was wrongly deleted"
fi

# --- Test 6: stale check DOES delete orphaned .mdc (no matching skill or rule) ---
TARGET6=$(mktemp -d); CLEANUP+=("$TARGET6")

mkdir -p "$TARGET6/.claude/hooks" "$TARGET6/.claude/rules" "$TARGET6/.cursor/rules"
cp "$REPO_ROOT/tests/fixtures/skill-rules.json" "$TARGET6/.claude/hooks/"

# Pre-create an orphaned .mdc with no matching skill dir or rule file
echo "orphan" > "$TARGET6/.cursor/rules/removed-skill.mdc"

bash "$SCRIPT" --cursor --apply --target "$TARGET6" > /dev/null

if [[ ! -f "$TARGET6/.cursor/rules/removed-skill.mdc" ]]; then
  ok "stale check: orphaned .mdc deleted"
else
  fail "stale check: orphaned .mdc not deleted"
fi

# --- Test 7: CLAUDE_PROTECTED_CURSOR_RULES skips protected skill ---
TARGET7=$(mktemp -d); CLEANUP+=("$TARGET7")

mkdir -p "$TARGET7/.claude/hooks"
cp "$REPO_ROOT/tests/fixtures/skill-rules.json" "$TARGET7/.claude/hooks/"

CLAUDE_PROTECTED_CURSOR_RULES="django-models" \
  bash "$SCRIPT" --cursor --apply --target "$TARGET7" > /dev/null

if [[ ! -f "$TARGET7/.cursor/rules/django-models.mdc" ]]; then
  ok "protected: django-models.mdc not created when protected"
else
  fail "protected: django-models.mdc was created despite protection"
fi

# Verify sync still ran (other skills were created)
OTHER_MDC=$(find "$TARGET7/.cursor/rules" -name "*.mdc" ! -name "django-models.mdc" 2>/dev/null | head -1)
if [[ -n "$OTHER_MDC" ]]; then
  ok "protected: sync ran — other .mdc files exist (protection ≠ total failure)"
else
  fail "protected: no other .mdc files found — sync may have failed entirely"
fi

# --- Test 8: SKIP_SKILLS excludes skill from sync ---
TARGET8=$(mktemp -d); CLEANUP+=("$TARGET8")

mkdir -p "$TARGET8/.claude/hooks"
cp "$REPO_ROOT/tests/fixtures/skill-rules.json" "$TARGET8/.claude/hooks/"

bash "$SCRIPT" --apply --target "$TARGET8" > /dev/null

if [[ ! -d "$TARGET8/.claude/skills/skill-creator" ]]; then
  ok "skip: skill-creator not synced (hardcoded in SKIP_SKILLS)"
else
  fail "skip: skill-creator was synced but should be excluded"
fi

# Verify other skills were still synced
OTHER_SKILL=$(find "$TARGET8/.claude/skills" -name "SKILL.md" ! -path "*/skill-creator/*" 2>/dev/null | head -1)
if [[ -n "$OTHER_SKILL" ]]; then
  ok "skip: other skills were still synced"
else
  fail "skip: no other skills found — sync may have failed entirely"
fi

# --- Summary ---
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
