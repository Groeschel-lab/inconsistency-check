# Contributing

Thanks for your interest. This repository is the **deployable tool** (a governed,
keyless LLM logic check) - not the research pipeline.

## Local development
See [Local development](README.md#local-development) in the README.

## Before opening a pull request
- CI must pass: the backend byte-compiles and imports, the reference-prompt test
  passes, `infra/main.bicep` builds, and all JSON files parse.
- If you change **`infra/main.bicep`**, rebuild the ARM template and commit both:
  ```bash
  az bicep build --file infra/main.bicep --outfile infra/main.json
  ```
- Keep it **dependency-light** and **keyless** by design: authentication is via
  Microsoft Entra ID managed identity + RBAC. Do **not** add API keys, connection
  strings, or Azure Key Vault.

## Never commit
- Secrets, API keys, `.env`, or `local.settings.json`.
- Patient data or any protected health information (PHI). The example letters in
  [`examples/`](examples/) are synthetic and fictional.

## Style
- Python: standard library first; small, readable functions; type hints where useful.
- Frontend: single dependency-free `frontend/index.html`.
