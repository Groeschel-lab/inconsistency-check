from __future__ import annotations

import ast
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def _runtime_prompt() -> str:
    module = ast.parse((ROOT / "backend" / "main.py").read_text(encoding="utf-8"))
    for node in module.body:
        if not isinstance(node, ast.Assign):
            continue
        if any(isinstance(target, ast.Name) and target.id == "_DEFAULT_SYSTEM_PROMPT" for target in node.targets):
            if isinstance(node.value, ast.Constant) and isinstance(node.value.value, str):
                return node.value.value
    raise AssertionError("_DEFAULT_SYSTEM_PROMPT not found")


class ReferencePromptTest(unittest.TestCase):
    def test_readme_prompt_matches_runtime_default(self) -> None:
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        match = re.search(
            r"<summary>German reference prompt used in the study</summary>\s*"
            r"```text\n(.*?)\n```",
            readme,
            re.DOTALL,
        )
        self.assertIsNotNone(match, "German reference prompt block not found in README")
        self.assertEqual(match.group(1), _runtime_prompt())


if __name__ == "__main__":
    unittest.main()