"""Unit tests for scripts/parse_skill_meta.py"""
import json
import os
import subprocess
import sys

import pytest

SCRIPT = os.path.join(os.path.dirname(__file__), "..", "scripts", "parse_skill_meta.py")


def run(path: str, query: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, SCRIPT, path, query],
        capture_output=True,
        text=True,
    )


class TestGetSkillMdField:
    def test_field_found(self, tmp_path):
        f = tmp_path / "SKILL.md"
        f.write_text("---\nname: test\ndescription: Django model patterns\n---\n\n# Body\n")
        result = run(str(f), "description")
        assert result.returncode == 0
        assert result.stdout.strip() == "Django model patterns"

    def test_field_not_found_returns_empty(self, tmp_path):
        f = tmp_path / "SKILL.md"
        f.write_text("---\nname: test\n---\n\n# Body\n")
        result = run(str(f), "description")
        assert result.returncode == 0
        assert result.stdout.strip() == ""

    def test_no_frontmatter_returns_empty(self, tmp_path):
        f = tmp_path / "SKILL.md"
        f.write_text("# No frontmatter here\nJust body.\n")
        result = run(str(f), "description")
        assert result.returncode == 0
        assert result.stdout.strip() == ""

    def test_file_not_found_exits_nonzero(self):
        result = run("/nonexistent/path/SKILL.md", "description")
        assert result.returncode != 0


class TestGetPathsList:
    def test_block_yaml_returns_json_array(self, tmp_path):
        f = tmp_path / "rule.md"
        f.write_text('---\ndescription: My rule\npaths:\n  - "**/tests/**"\n  - "**/test_*"\n---\n\n# Body\n')
        result = run(str(f), "paths")
        assert result.returncode == 0
        assert json.loads(result.stdout.strip()) == ["**/tests/**", "**/test_*"]

    def test_empty_paths_field_returns_empty_array(self, tmp_path):
        f = tmp_path / "rule.md"
        f.write_text("---\ndescription: My rule\npaths:\n---\n\n# Body\n")
        result = run(str(f), "paths")
        assert result.returncode == 0
        assert json.loads(result.stdout.strip()) == []

    def test_no_paths_field_returns_empty_array(self, tmp_path):
        f = tmp_path / "rule.md"
        f.write_text("---\ndescription: My rule\n---\n\n# Body\n")
        result = run(str(f), "paths")
        assert result.returncode == 0
        assert json.loads(result.stdout.strip()) == []

    def test_file_not_found_exits_nonzero(self):
        result = run("/nonexistent/path/rule.md", "paths")
        assert result.returncode != 0


class TestGetGlobs:
    def test_globs_found(self, tmp_path):
        rules = {
            "skills": {
                "django-models": {
                    "triggers": {
                        "pathPatterns": ["**/models.py", "**/models/*.py"]
                    }
                }
            }
        }
        f = tmp_path / "skill-rules.json"
        f.write_text(json.dumps(rules))
        result = run(str(f), "globs:django-models")
        assert result.returncode == 0
        assert json.loads(result.stdout.strip()) == ["**/models.py", "**/models/*.py"]

    def test_skill_not_found_returns_empty_array(self, tmp_path):
        f = tmp_path / "skill-rules.json"
        f.write_text('{"skills": {}}')
        result = run(str(f), "globs:nonexistent")
        assert result.returncode == 0
        assert result.stdout.strip() == "[]"
