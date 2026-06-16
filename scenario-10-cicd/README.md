# Scenario 10 — CI/CD for Bedrock Workloads

## Goal

Automate infrastructure provisioning and model evaluation with AWS CodePipeline,
demonstrating a production-grade delivery workflow for generative AI applications.

## Infrastructure deployed

| Resource | Purpose |
|---|---|
| CodePipeline | Orchestrates Source → Build → Evaluate → Deploy stages |
| CodeBuild project | Runs `terraform plan/apply` and Bedrock evaluation quality checks |
| S3 bucket (artifacts) | Stores pipeline stage artifacts and saved Terraform plans |
| IAM roles | Least-privilege CodePipeline and CodeBuild service roles |
| SNS topic | Delivers pipeline failure notifications |

## Key concepts

- **Infrastructure as code in CI** — gating Terraform `apply` behind a plan review step prevents surprise changes reaching production.
- **Model evaluation gating** — running a lightweight evaluation job in the pipeline and blocking deploy on a score regression catches quality regressions before they reach users.
- **Blue/green deployment** — route traffic between Lambda function versions using weighted aliases; enables instant cutover or rollback.
- **Canary releases** — gradually shift inference traffic using a CodeDeploy Lambda deployment configuration with automatic rollback triggers.
- **Rollback triggers** — a CloudWatch alarm breach automatically invokes CodeDeploy rollback; pair with latency or error-rate alarms.

## What to observe

1. Push a change to the monitored branch; watch CodePipeline advance through each stage in the console.
2. Introduce a Terraform syntax error; confirm the Build stage fails and blocks the downstream Deploy stage.
3. Lower the evaluation score threshold and observe whether the Evaluate stage blocks on a score regression.
4. Trigger a manual approval gate and confirm the pipeline pauses until approved.
5. Inspect CloudTrail for the CodeBuild service role's API calls to Bedrock during the evaluation step.
