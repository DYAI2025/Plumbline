import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SKILLS_DIR = ROOT / "config" / "claude" / "skills"
COMMANDS_DIR = ROOT / "config" / "claude" / "commands"
INSTALL = ROOT / "config" / "claude" / "install.sh"

EXPECTED_SKILLS = {
    "ai-native-prd-architect": "ai-native-prd-architect",
    "brainstorming": "brainstorming",
    "ultrathink-craftsmanship": "ultrathink-craftsmanship",
    "konfabulations-audit": "konfabulations-audit",
    "root-cause-tracing": "root-cause-tracing",
    "systematic-debugging": "systematic-debugging",
    "test-driven-development": "test-driven-development",
    "executing-plans": "executing-plans",
    "writing-plans": "writing-plans",
    "writing-skills": "writing-skills",
    "product-management-write-spec": "product-management-write-spec",
    "using-git-worktrees": "using-git-worktrees",
    "defense-in-depth": "defense-in-depth",
    "testing-anti-patterns": "testing-anti-patterns",
    "claude-reflect": "claude-reflect",
    "skill-creator": "skill-creator",
}

SKILL_REF_PATTERNS = [
    re.compile(r"Skill `([^`]+)`"),
    re.compile(r"`([a-z][a-z0-9-]+(?::[a-z0-9-]+)?)`"),
    re.compile(r"/([a-z][a-z0-9-]+(?::[a-z0-9-]+)?)"),
]

IGNORED_BACKTICKS = {
    "agileteam",
    "agileteam-bench",
    "reflect",
    "reflect-skills",
    "metrics/runs.jsonl",
    "docs/agileteam-spec-v3.md",
    "docs/agileteam-governance.md",
    "config/claude/skills/agent-learning-loop.json",
}


class ClaudeSetupTests(unittest.TestCase):
    def test_expected_skills_are_vendored_with_valid_frontmatter(self):
        for skill_name, dirname in EXPECTED_SKILLS.items():
            with self.subTest(skill=skill_name):
                skill_file = SKILLS_DIR / dirname / "SKILL.md"
                self.assertTrue(skill_file.exists(), f"missing {skill_file}")
                text = skill_file.read_text(encoding="utf-8")
                self.assertTrue(text.startswith("---\n"), f"{skill_file} lacks frontmatter")
                frontmatter = text.split("---", 2)[1]
                self.assertIn(f"name: {skill_name}", frontmatter)
                self.assertRegex(frontmatter, r"(?m)^description: .{20,}$")

    def test_skill_references_in_workflow_docs_are_vendored_or_fallback_commands(self):
        scanned = [
            ROOT / "config" / "claude" / "commands" / "agileteam.md",
            ROOT / "docs" / "agileteam-spec-v3.md",
            ROOT / "SETUP.md",
            ROOT / "CLAUDE.md",
            ROOT / "config" / "claude" / "skills" / "agent-learning-loop.json",
        ]
        found = set()
        for path in scanned:
            text = path.read_text(encoding="utf-8")
            for pattern in SKILL_REF_PATTERNS:
                found.update(match.group(1) for match in pattern.finditer(text))

        skill_like = {
            item
            for item in found
            if item in EXPECTED_SKILLS or item in {"reflect", "reflect-skills"}
        }
        missing_skills = sorted(
            item for item in skill_like if item in EXPECTED_SKILLS and not (SKILLS_DIR / EXPECTED_SKILLS[item] / "SKILL.md").exists()
        )
        self.assertEqual([], missing_skills)
        for command in ("reflect", "reflect-skills"):
            with self.subTest(command=command):
                self.assertTrue((COMMANDS_DIR / f"{command}.md").exists())

    def test_installer_dry_run_covers_agents_commands_and_all_skills(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = os.environ.copy()
            env["CLAUDE_HOME"] = tmp
            result = subprocess.run(
                [str(INSTALL), "--dry-run"],
                cwd=ROOT,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
            )
        output = result.stdout
        self.assertIn("would symlink", output)
        self.assertIn(f"{tmp}/agents", output)
        for command in ("agileteam", "agileteam-bench", "reflect", "reflect-skills"):
            self.assertIn(f"{tmp}/commands/{command}.md", output)
        for dirname in EXPECTED_SKILLS.values():
            self.assertIn(f"{tmp}/skills/{dirname}", output)
        self.assertIn("would register stop-hook", output)

    def test_installer_copy_mode_without_hook_materializes_portable_cli(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = os.environ.copy()
            env["CLAUDE_HOME"] = tmp
            subprocess.run(
                [str(INSTALL), "--copy", "--no-agents", "--no-hook"],
                cwd=ROOT,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
            )
            home = Path(tmp)
            self.assertTrue((home / "commands" / "agileteam.md").exists())
            self.assertTrue((home / "commands" / "reflect-skills.md").exists())
            for dirname in EXPECTED_SKILLS.values():
                self.assertTrue((home / "skills" / dirname / "SKILL.md").exists())


if __name__ == "__main__":
    unittest.main()
