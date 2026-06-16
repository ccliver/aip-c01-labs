# Scenario 08 — Model Evaluation

## Goal

Run Amazon Bedrock Model Evaluation jobs to benchmark and compare models on a curated
Q&A dataset, then analyse the resulting metrics to make evidence-based model selection
decisions.

## Infrastructure deployed

| Resource | Purpose |
|---|---|
| S3 bucket (eval) | Hosts the evaluation dataset (JSONL) and receives result reports |
| IAM role | `bedrock:CreateEvaluationJob` + S3 read/write for the evaluation service |
| Evaluation job trigger | `null_resource` executing `aws bedrock create-evaluation-job` |

## Key concepts

- **Automatic evaluation** — uses built-in metrics (accuracy, robustness, toxicity) against a JSONL ground-truth dataset; no human labellers required.
- **Human evaluation** — routes model outputs to an Amazon SageMaker Ground Truth work team for side-by-side preference ranking.
- **ROUGE / BERTScore** — summarisation metrics; a lower ROUGE score does not always mean lower quality — use them as signals, not verdicts.
- **Model comparison** — a single job can evaluate multiple model IDs and produce a comparative leaderboard.
- **Evaluation dataset format** — JSONL with `prompt` and optional `referenceResponse` fields; see the Bedrock docs for task-specific schema requirements.

## What to observe

1. Upload `data/eval_dataset.jsonl` to the eval bucket and start the job.
2. Wait for job completion (typically 10–30 minutes) and download the results report from S3.
3. Compare Haiku vs. Nova Lite on accuracy, coherence, and fluency scores.
4. Deliberately introduce wrong reference answers into the dataset and re-run; observe the score impact on the affected metric.
