# Release checklist

Work through this before making the repository public / tagging a public release.

## Publication repository
The public home is **`groeschel-lab/inconsistency-check`**. Before each public
release, verify the owner in every hard-coded URL:
- [ ] `README.md` - the **Deploy to Azure** button
- [ ] `infra/main.bicep` and generated `infra/main.json` - `packageUri` default
- [ ] `CITATION.cff` - `repository-code`
- [ ] The paper's *Code Availability* statement

## Verify before first deploy
- [ ] Confirm model **names, versions, SKUs** in `infra/main.bicep` against the live
      Azure AI Foundry catalog, and check **regional quota** for the chosen profile.
- [ ] Rebuild the ARM template if Bicep changed: `az bicep build --file infra/main.bicep --outfile infra/main.json`.

## Build + smoke test
- [ ] Refresh the pinned dependency versions in `requirements.txt` (command is in the file header).
- [ ] Tag `v0.2.0` and confirm the `release` workflow attaches `app.zip` to the release.
- [ ] **Order matters:** `infra/main.bicep` pins `packageUri` to a specific tag, so the release must
      exist in `groeschel-lab` *before* `infra/main.json` reaches `main`. Otherwise the deployment
      button points at a missing asset.
- [ ] End-to-end test the **Deploy to Azure** button in a real subscription: portal
      wizard → resources created → open the frontend URL → paste an example letter →
      findings render.

## Finalize metadata
- [ ] `CITATION.cff` author list matches the published paper (co-authors, order, ORCIDs, affiliations).
- [ ] Verify the public contacts in `SECURITY.md` and `CODE_OF_CONDUCT.md`.
- [ ] Confirm `LICENSE` and the intended-use statements have been reviewed by the responsible organization.
