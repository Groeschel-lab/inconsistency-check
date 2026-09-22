from __future__ import annotations

import unittest
from unittest.mock import patch

from fastapi import HTTPException

from backend import main


class InputLimitTest(unittest.TestCase):
    def test_oversized_text_is_rejected_before_any_model_call(self) -> None:
        with patch.object(main, "_bearer_token") as bearer_token:
            with self.assertRaises(HTTPException) as raised:
                main.analyze(main.AnalyzeRequest(text="x" * (main.MAX_INPUT_CHARS + 1)))

        self.assertEqual(raised.exception.status_code, 413)
        bearer_token.assert_not_called()

    def test_empty_text_is_rejected_before_any_model_call(self) -> None:
        with patch.object(main, "_bearer_token") as bearer_token:
            with self.assertRaises(HTTPException) as raised:
                main.analyze(main.AnalyzeRequest(text="   "))

        self.assertEqual(raised.exception.status_code, 400)
        bearer_token.assert_not_called()


class ModelResponseValidationTest(unittest.TestCase):
    def test_non_json_response_is_not_treated_as_no_findings(self) -> None:
        with self.assertRaises(ValueError):
            main._extract_issues("not valid JSON")

    def test_valid_empty_response_remains_supported(self) -> None:
        self.assertEqual(main._extract_issues('{"issues": []}'), [])

    def test_unknown_field_in_model_response_is_rejected(self) -> None:
        payload = '{"issues": [{"description": "d", "context": "c", "category": "Zeitlich", ' \
                  '"severity": 5, "rationale": "r", "clinical_impact": "i", "correction": "x", "extra": 1}]}'
        with self.assertRaises(ValueError):
            main._extract_issues(payload)


if __name__ == "__main__":
    unittest.main()