# Release checklist

Work through this before making the repository public / tagging a public release.

## Repository move + URL flip
The interim staging owner is `helloworld-germany`; the final home is
**`groeschel-lab/inconsistency-check`**. Before public release, flip the owner in
every hard-coded URL:
- [ ] `README.md` - the **Deploy to Azure** button (two `raw.githubusercontent.com` URLs)
- [ ] `infra/main.bicep` - `packageUri` default (GitHub releases URL)
- [ ] `CITATION.cff` - `repository-code`
- [ ] The paper's *Code Availability* statement

## Verify before first deploy
- [ ] Confirm model **names, versions, SKUs** in `infra/main.bicep` against the live
      Azure AI Foundry catalog, and check **regional quota** for the chosen profile.
- [ ] Rebuild the ARM template if Bicep changed: `az bicep build --file infra/main.bicep --outfile infra/main.json`.

## Build + smoke test
- [ ] Tag `v1.0.0` and confirm the `release` workflow attaches `app.zip` to the release.
- [ ] End-to-end test the **Deploy to Azure** button in a real subscription: portal
      wizard → resources created → open the frontend URL → paste an example letter →
      findings render.

## Finalize metadata
- [ ] `CITATION.cff` author list matches the published paper (co-authors, order, ORCIDs, affiliations).
- [ ] Fill the `SECURITY.md` and `CODE_OF_CONDUCT.md` contact placeholders.
- [ ] Confirm `LICENSE` and the "not a medical device" disclaimers are present.
