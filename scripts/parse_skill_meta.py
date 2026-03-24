#!/usr/bin/env python3
"""Извлекает метаданные из SKILL.md frontmatter или skill-rules.json.

Использование:
  parse_skill_meta.py path/to/SKILL.md description
  parse_skill_meta.py path/to/skill-rules.json globs:django-models
"""
import json
import sys


def get_skill_md_field(path: str, field: str) -> str:
    try:
        lines = open(path).readlines()
    except IOError as e:
        print(f"Error reading {path}: {e}", file=sys.stderr)
        sys.exit(1)
    in_front, count = False, 0
    for line in lines:
        if line.strip() == "---":
            count += 1
            in_front = count == 1
            if count == 2:
                break
            continue
        if in_front and line.startswith(f"{field}:"):
            return line.split(":", 1)[1].strip().strip('"')
    return ""


def get_globs(rules_path: str, skill_name: str) -> str:
    try:
        d = json.load(open(rules_path))
    except IOError as e:
        print(f"Error reading {rules_path}: {e}", file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"Invalid JSON in {rules_path}: {e}", file=sys.stderr)
        sys.exit(1)
    patterns = (d.get("skills", {})
                 .get(skill_name, {})
                 .get("triggers", {})
                 .get("pathPatterns", []))
    return json.dumps(patterns)


path, query = sys.argv[1], sys.argv[2]
if query.startswith("globs:"):
    print(get_globs(path, query.split(":", 1)[1]))
else:
    print(get_skill_md_field(path, query))
