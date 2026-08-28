# Security Policy

## Reporting a vulnerability
Please report suspected vulnerabilities privately to the maintainers at
**[maintainer security contact - fill before release]**. Do not open a public
issue for security reports. We aim to acknowledge reports within a few business days.

## Design principles
- **Keyless.** All Azure calls use Microsoft Entra ID managed identity + scoped
  RBAC. There are no API keys, connection strings, or Azure Key Vault.
- **No persistence of clinical text.** Submitted text is processed in memory and
  is not stored; logs contain only status codes and durations.
- **Tenant-contained.** Everything is provisioned inside your own Azure tenant via
  Infrastructure as Code.

## Not a medical device
This software is **not** a medical device (MDR/IVDR). All findings must be
verified by a qualified clinician.

## Supported versions
The latest tagged release on the default branch is supported.
