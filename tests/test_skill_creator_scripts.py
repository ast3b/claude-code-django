"""Unit tests for .claude/skills/skill-creator/scripts/

Covers:
  - init_skill.py   — directory scaffolding and frontmatter generation
  - package_skill.py — validation gate + .skill archive creation
  - quick_validate.py — frontmatter rules (name, description, structure)
"""
import os
import subprocess
import sys
import zipfile
from pathlib import Path

import pytest

SCRIPTS_DIR = Path(__file__).parent.parent / ".claude/skills/skill-creator/scripts"
INIT = str(SCRIPTS_DIR / "init_skill.py")
PACKAGE = str(SCRIPTS_DIR / "package_skill.py")
VALIDATE = str(SCRIPTS_DIR / "quick_validate.py")


def run(script: str, *args: str, cwd: Path | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, script, *args],
        capture_output=True,
        text=True,
        cwd=str(cwd) if cwd else None,
    )


def make_valid_skill(root: Path, name: str = "my-skill") -> Path:
    """Create a minimal valid skill directory for use in tests."""
    skill_dir = root / name
    skill_dir.mkdir(parents=True)
    (skill_dir / "SKILL.md").write_text(
        f"---\nname: {name}\ndescription: Does something useful\n---\n\n# Body\n"
    )
    return skill_dir


# ---------------------------------------------------------------------------
# init_skill.py
# ---------------------------------------------------------------------------


class TestInitSkill:
    def test_creates_directory_structure(self, tmp_path):
        result = run(INIT, "test-skill", "--path", str(tmp_path))
        assert result.returncode == 0
        skill_dir = tmp_path / "test-skill"
        assert skill_dir.is_dir()
        assert (skill_dir / "SKILL.md").is_file()
        assert (skill_dir / "scripts").is_dir()
        assert (skill_dir / "references").is_dir()
        assert (skill_dir / "assets").is_dir()

    def test_skill_md_has_name_in_frontmatter(self, tmp_path):
        run(INIT, "my-skill", "--path", str(tmp_path))
        content = (tmp_path / "my-skill" / "SKILL.md").read_text()
        assert "name: my-skill" in content

    def test_skill_md_has_description_field(self, tmp_path):
        run(INIT, "my-skill", "--path", str(tmp_path))
        content = (tmp_path / "my-skill" / "SKILL.md").read_text()
        assert "description:" in content

    def test_skill_md_has_frontmatter_delimiters(self, tmp_path):
        run(INIT, "my-skill", "--path", str(tmp_path))
        lines = (tmp_path / "my-skill" / "SKILL.md").read_text().splitlines()
        assert lines[0] == "---", "SKILL.md must start with ---"
        assert "---" in lines[1:], "SKILL.md must close frontmatter with ---"

    def test_example_script_is_executable(self, tmp_path):
        run(INIT, "my-skill", "--path", str(tmp_path))
        script = tmp_path / "my-skill" / "scripts" / "example.py"
        assert script.is_file()
        assert os.access(script, os.X_OK)

    def test_existing_directory_exits_nonzero(self, tmp_path):
        run(INIT, "dupe-skill", "--path", str(tmp_path))
        result = run(INIT, "dupe-skill", "--path", str(tmp_path))
        assert result.returncode != 0

    def test_missing_args_exits_nonzero(self):
        result = run(INIT)
        assert result.returncode != 0


# ---------------------------------------------------------------------------
# quick_validate.py
# ---------------------------------------------------------------------------


class TestQuickValidate:
    def test_valid_skill_passes(self, tmp_path):
        skill_dir = make_valid_skill(tmp_path)
        result = run(VALIDATE, str(skill_dir))
        assert result.returncode == 0
        assert "valid" in result.stdout.lower()

    def test_missing_skill_md_fails(self, tmp_path):
        empty_dir = tmp_path / "empty-skill"
        empty_dir.mkdir()
        result = run(VALIDATE, str(empty_dir))
        assert result.returncode != 0

    def test_missing_name_fails(self, tmp_path):
        skill_dir = tmp_path / "no-name"
        skill_dir.mkdir()
        (skill_dir / "SKILL.md").write_text(
            "---\ndescription: Missing name\n---\n\n# Body\n"
        )
        result = run(VALIDATE, str(skill_dir))
        assert result.returncode != 0

    def test_missing_description_fails(self, tmp_path):
        skill_dir = tmp_path / "no-desc"
        skill_dir.mkdir()
        (skill_dir / "SKILL.md").write_text("---\nname: no-desc\n---\n\n# Body\n")
        result = run(VALIDATE, str(skill_dir))
        assert result.returncode != 0

    def test_name_too_long_fails(self, tmp_path):
        long_name = "a" * 65
        skill_dir = tmp_path / long_name
        skill_dir.mkdir()
        (skill_dir / "SKILL.md").write_text(
            f"---\nname: {long_name}\ndescription: Something\n---\n\n# Body\n"
        )
        result = run(VALIDATE, str(skill_dir))
        assert result.returncode != 0

    def test_name_with_uppercase_fails(self, tmp_path):
        skill_dir = tmp_path / "BadName"
        skill_dir.mkdir()
        (skill_dir / "SKILL.md").write_text(
            "---\nname: BadName\ndescription: Something\n---\n\n# Body\n"
        )
        result = run(VALIDATE, str(skill_dir))
        assert result.returncode != 0

    def test_description_with_angle_brackets_fails(self, tmp_path):
        skill_dir = tmp_path / "angle-skill"
        skill_dir.mkdir()
        (skill_dir / "SKILL.md").write_text(
            "---\nname: angle-skill\ndescription: Use <br> tags\n---\n\n# Body\n"
        )
        result = run(VALIDATE, str(skill_dir))
        assert result.returncode != 0

    def test_no_frontmatter_fails(self, tmp_path):
        skill_dir = tmp_path / "no-front"
        skill_dir.mkdir()
        (skill_dir / "SKILL.md").write_text("# Just a heading\nNo frontmatter here.\n")
        result = run(VALIDATE, str(skill_dir))
        assert result.returncode != 0

    def test_missing_arg_exits_nonzero(self):
        result = run(VALIDATE)
        assert result.returncode != 0


# ---------------------------------------------------------------------------
# package_skill.py
# ---------------------------------------------------------------------------


class TestPackageSkill:
    def test_valid_skill_creates_skill_file(self, tmp_path):
        skill_dir = make_valid_skill(tmp_path)
        output_dir = tmp_path / "dist"
        result = run(
            PACKAGE,
            str(skill_dir),
            str(output_dir),
            cwd=SCRIPTS_DIR,
        )
        assert result.returncode == 0
        skill_file = output_dir / "my-skill.skill"
        assert skill_file.is_file()

    def test_skill_file_is_valid_zip(self, tmp_path):
        skill_dir = make_valid_skill(tmp_path)
        output_dir = tmp_path / "dist"
        run(PACKAGE, str(skill_dir), str(output_dir), cwd=SCRIPTS_DIR)
        skill_file = output_dir / "my-skill.skill"
        assert zipfile.is_zipfile(skill_file)

    def test_skill_file_contains_skill_md(self, tmp_path):
        skill_dir = make_valid_skill(tmp_path)
        output_dir = tmp_path / "dist"
        run(PACKAGE, str(skill_dir), str(output_dir), cwd=SCRIPTS_DIR)
        skill_file = output_dir / "my-skill.skill"
        with zipfile.ZipFile(skill_file) as zf:
            names = zf.namelist()
        assert any("SKILL.md" in n for n in names)

    def test_invalid_skill_exits_nonzero(self, tmp_path):
        bad_skill_dir = tmp_path / "bad-skill"
        bad_skill_dir.mkdir()
        # Missing description — should fail validation
        (bad_skill_dir / "SKILL.md").write_text("---\nname: bad-skill\n---\n\n# Body\n")
        result = run(PACKAGE, str(bad_skill_dir), cwd=SCRIPTS_DIR)
        assert result.returncode != 0

    def test_missing_skill_md_exits_nonzero(self, tmp_path):
        empty_dir = tmp_path / "empty-skill"
        empty_dir.mkdir()
        result = run(PACKAGE, str(empty_dir), cwd=SCRIPTS_DIR)
        assert result.returncode != 0

    def test_nonexistent_path_exits_nonzero(self, tmp_path):
        result = run(
            PACKAGE,
            str(tmp_path / "does-not-exist"),
            cwd=SCRIPTS_DIR,
        )
        assert result.returncode != 0
