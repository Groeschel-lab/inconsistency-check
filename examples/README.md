# Examples

**Synthetic, fictional, PHI-free** German discharge letters with deliberately
planted internal inconsistencies. They contain **no real patient data** - all
names, dates, and values are invented - and exist only to demo and smoke-test
the tool.

| File | Planted issues |
|---|---|
| [`example1_discharge_letter.txt`](example1_discharge_letter.txt) | admission-after-discharge date, CRP "fall" to a higher value, antibiotic despite a documented penicillin allergy, an implausible drug-dose unit, a gender mismatch, a follow-up date in the past |
| [`example2_discharge_letter.txt`](example2_discharge_letter.txt) | drug given despite a documented intolerance, a contradictory fever course |

Each `*_expected_findings.json` lists the **planted** inconsistencies. They are
illustrative - a capable model should surface at least these, but exact wording,
count, and severity vary by model.

## Use

**Web app:** paste a letter's text into the deployed frontend and click *Analyze*.

**API:**
```bash
curl -sS -X POST "$BACKEND_URL/api/analyze" \
  -H "Content-Type: application/json" \
  --data "$(jq -Rs '{text: .}' examples/example1_discharge_letter.txt)"
```

> These files are for demonstration only and must never be treated as clinical
> guidance.
