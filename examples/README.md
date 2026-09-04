# Examples

These **synthetic, fictional, PHI-free** discharge summaries contain no real
patient data. All names, dates, and values are invented.

The German files are the reference examples. The English files are convenience
translations for international users and were not used in the study.

| Example | Language | Planted issues |
|---|---|---|
| [`example1_discharge_letter.txt`](example1_discharge_letter.txt) | German reference | admission after discharge, CRP "decrease" to a higher value, penicillin despite allergy, implausible dose unit, gender mismatch, follow-up before discharge |
| [`example1_discharge_letter_en.txt`](example1_discharge_letter_en.txt) | English translation | translated equivalent of German example 1 |
| [`example2_discharge_letter.txt`](example2_discharge_letter.txt) | German reference | ciprofloxacin despite intolerance, contradictory fever course |
| [`example2_discharge_letter_en.txt`](example2_discharge_letter_en.txt) | English translation | translated equivalent of German example 2 |

Each `*_expected_findings*.json` file lists the planted inconsistencies. Exact
wording, count, and severity can vary by model.

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
