#!/usr/bin/env python3
"""Extract metadata from SKILL.md/rules frontmatter or skill-rules.json.

Usage:
  parse_skill_meta.py path/to/SKILL.md description
  parse_skill_meta.py path/to/skill-rules.json globs:django-models
  parse_skill_meta.py path/to/rules/core-testing.md paths
"""
import json
import sys


def _read_lines(path: str) -> list[str]:
    try:
        with open(path) as f:
            return f.readlines()
    except (IOError, UnicodeDecodeError) as e:
        print(f"Error reading {path}: {e}", file=sys.stderr)
        sys.exit(1)


def get_skill_md_field(path: str, field: str) -> str:
    in_front, count = False, 0
    for line in _read_lines(path):
        if line.strip() == "---":
            count += 1
            in_front = count == 1
            if count == 2:
                break
            continue
        if in_front and line.startswith(f"{field}:"):
            return line.split(":", 1)[1].strip().strip('"')
    return ""


def get_paths_list(path: str) -> str:
    in_front, count, in_paths = False, 0, False
    patterns: list[str] = []
    for line in _read_lines(path):
        if line.strip() == "---":
            count += 1
            in_front = count == 1
            in_paths = False
            if count == 2:
                break
            continue
        if not in_front:
            continue
        if line.startswith("paths:"):
            # Only block-style YAML lists are supported (  - "pattern").
            # Inline lists (paths: ["..."]) are not parsed.
            in_paths = True
            continue
        if in_paths and line.startswith("  - "):
            item = line.strip()[2:]
            patterns.append(item.strip('"').strip("'"))
        elif in_paths:
            in_paths = False
    return json.dumps(patterns)


def get_globs(rules_path: str, skill_name: str) -> str:
    try:
        with open(rules_path) as f:
            d = json.load(f)
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
elif query == "paths":
    print(get_paths_list(path))
else:
    print(get_skill_md_field(path, query))
