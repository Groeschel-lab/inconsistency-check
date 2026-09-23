# Security Policy

## Reporting a vulnerability
Please report suspected vulnerabilities privately to the maintainers at
**matthias.groeschel@charite.de**. Do not open a public
issue for security reports. We aim to acknowledge reports within a few business days.

## Design principles
- **Keyless.** All Azure calls use Microsoft Entra ID managed identity + scoped
  RBAC. There are no API keys, connection strings, or Azure Key Vault, and FTP/SCM
  basic publishing credentials are disabled.
- **No persistence of clinical text by this application.** Submitted text is
  processed in memory and is not stored by the app; its logs contain only status
  codes and durations. The model platform may still retain prompts and completions
  for abuse monitoring - see the *Data handling* section of the README.
- **Tenant-contained.** Everything is provisioned inside your own Azure tenant via
  Infrastructure as Code. Model deployments default to the EU data zone
  (`DataZoneStandard`); Claude Opus 4.7 and DeepSeek V3.2 are only offered as
  `GlobalStandard` and may be processed outside the EU.

## Intended use
**Research prototype.** Use only within an organizationally approved setting;
qualified clinicians must review every finding. It is not a medical device, is not
CE-marked, and must not be used for clinical decision-making.

## Supported versions
The latest tagged release on the default branch is supported.
