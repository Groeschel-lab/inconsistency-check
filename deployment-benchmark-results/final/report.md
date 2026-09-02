# Deployment-to-model-response time

The complete IaC deployment reached its first valid model response within minutes rather than days. Across 25 completed deployments, the median was 231.9 s and the range was 144.5–953.1 s. Model-specific dispersion differed, as shown below.

| Model | n | Mean (s) | Sample SD (s) | Median (s) | Range (s) |
|---|---:|---:|---:|---:|---:|
| Claude Opus 4.7 | 4 | 258.3 | 37.6 | 257.6 | 217.3–300.5 |
| GPT-5.5 | 6 | 294.8 | 181.7 | 244.4 | 150.7–656.6 |
| Mistral Large 3 | 4 | 500.3 | 355.3 | 428.5 | 191.0–953.1 |
| DeepSeek V3.2 | 6 | 277.0 | 171.3 | 227.5 | 144.5–619.6 |
| GPT-5.4 nano | 5 | 232.9 | 129.6 | 176.4 | 168.7–464.6 |

![Deployment time by model](deployment-time-by-model.png)

**Figure.** Time from submission of the commit-pinned ARM template to the first valid model response. Points show individual deployments, diamonds show arithmetic means, and vertical lines show ranges.

Measurements without a returned result were repeated; only completed deployments were included in the descriptive timing summary.

The 25 values are the chronologically first successful measurements across the two original benchmark runs. Both runs used the same region, model capacity, probe, endpoint contract, ARM template hash, and application package hash.
