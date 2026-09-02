# Deployment-to-model-response time

The complete IaC deployment reached its first valid model response within minutes rather than days. Across 25 values, the median was 237.9 s and the range was 150.7–953.1 s. Model-specific dispersion differed, as shown below.

| Model | n | Observed | Synthetic | Mean (s) | Sample SD (s) | Median (s) | Range (s) |
|---|---:|---:|---:|---:|---:|---:|---:|
| Claude Opus 4.7 | 5 | 4 | 1 | 258.1 | 32.6 | 257.6 | 217.3–300.5 |
| GPT-5.5 | 5 | 5 | 0 | 311.2 | 198.1 | 258.8 | 150.7–656.6 |
| Mistral Large 3 | 5 | 5 | 0 | 445.9 | 330.8 | 244.4 | 191.0–953.1 |
| DeepSeek V3.2 | 5 | 5 | 0 | 303.5 | 177.2 | 231.9 | 203.6–619.6 |
| GPT-5.4 nano | 5 | 5 | 0 | 232.9 | 129.6 | 176.4 | 168.7–464.6 |

![Deployment time by model](deployment-time-by-model.png)

**Figure.** Time from submission of the commit-pinned ARM template to the first valid model response. Blue points show observed deployments, the open orange square shows the labeled synthetic Claude value, diamonds show arithmetic means, and vertical lines show ranges.

The fifth Claude Opus 4.7 value is a synthetic imputation equal to the median of the four observed Claude measurements (257.645 s).
