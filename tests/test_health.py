from __future__ import annotations

import unittest
from unittest.mock import patch

from backend import main


class HealthTest(unittest.TestCase):
    def test_health_exposes_institution_name(self) -> None:
        with patch.object(main, "INSTITUTION_NAME", "Sample Hospital"):
            self.assertEqual(main.health()["institution"], "Sample Hospital")


if __name__ == "__main__":
    unittest.main()