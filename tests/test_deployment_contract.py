from __future__ import annotations

import json
import unittest
from pathlib import Path
from typing import Any, Iterator


ROOT = Path(__file__).resolve().parents[1]
PACKAGE_URI = "https://github.com/groeschel-lab/inconsistency-check/releases/latest/download/app.zip"


def _objects(value: Any) -> Iterator[dict[str, Any]]:
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from _objects(child)
    elif isinstance(value, list):
        for child in value:
            yield from _objects(child)


class DeploymentContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.template = json.loads((ROOT / "infra" / "main.json").read_text(encoding="utf-8"))
        cls.form = json.loads((ROOT / "infra" / "uiFormDefinition.json").read_text(encoding="utf-8"))

    def test_package_uri_targets_publication_repository(self) -> None:
        self.assertEqual(self.template["parameters"]["packageUri"]["defaultValue"], PACKAGE_URI)

    def test_function_app_allows_its_own_origin(self) -> None:
        sites = [item for item in _objects(self.template) if item.get("type") == "Microsoft.Web/sites"]
        self.assertEqual(len(sites), 1)
        cors = sites[0]["properties"]["siteConfig"]["cors"]
        self.assertFalse(cors["supportCredentials"])
        self.assertEqual(len(cors["allowedOrigins"]), 1)
        self.assertIn("functionAppName", cors["allowedOrigins"][0])
        self.assertIn(".azurewebsites.net", cors["allowedOrigins"][0])

    def test_institution_name_reaches_function_app(self) -> None:
        parameter = self.template["parameters"]["institutionName"]
        self.assertEqual(parameter["defaultValue"], "")
        self.assertEqual(parameter["maxLength"], 60)

        settings = [item["institutionSetting"] for item in _objects(self.template) if "institutionSetting" in item]
        self.assertEqual(len(settings), 1)
        self.assertIn("INSTITUTION_NAME", settings[0])
        self.assertIn("parameters('institutionName')", settings[0])

        sites = [item for item in _objects(self.template) if item.get("type") == "Microsoft.Web/sites"]
        app_settings = sites[0]["properties"]["siteConfig"]["appSettings"]
        self.assertIn("variables('institutionSetting')", app_settings)

    def test_wizard_collects_institution_name(self) -> None:
        properties = self.form["view"]["properties"]
        basics = next(step for step in properties["steps"] if step["name"] == "basics")
        field = next(element for element in basics["elements"] if element["name"] == "institutionName")
        self.assertEqual(field["type"], "Microsoft.Common.TextBox")
        self.assertEqual(field["constraints"]["regex"], "^.{0,60}$")
        self.assertEqual(
            properties["outputs"]["parameters"]["institutionName"],
            "[steps('basics').institutionName]",
        )

    def test_wizard_defaults_to_sign_in(self) -> None:
        properties = self.form["view"]["properties"]
        access = next(step for step in properties["steps"] if step["name"] == "access")
        mode = next(element for element in access["elements"] if element["name"] == "authMode")
        self.assertEqual(mode["defaultValue"], "entra")
        labels = {item["value"]: item["label"] for item in mode["constraints"]["allowedValues"]}
        self.assertIn("recommended", labels["entra"].lower())
        self.assertIn("separately", labels["none"].lower())


if __name__ == "__main__":
    unittest.main()