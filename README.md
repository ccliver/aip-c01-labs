# aip-c01-labs

Hands-on lab curriculum for the **AWS Certified AI Practitioner (AIP-C01)** exam,
covering Amazon Bedrock, RAG pipelines, prompt engineering, guardrails, governance,
cost control, and CI/CD for generative AI workloads.

---

## Scenario list

| # | Folder | What it covers |
|---|--------|----------------|
| 01 | [scenario-01-embeddings](./scenario-01-embeddings/) | Generate and store text embeddings with Amazon Titan Embeddings V2 |
| 02 | [scenario-02-knowledge-bases](./scenario-02-knowledge-bases/) | Build a Bedrock Knowledge Base backed by OpenSearch Serverless |
| 03 | [scenario-03-advanced-retrieval](./scenario-03-advanced-retrieval/) | Metadata filtering, hybrid search, and reranking on top of a Knowledge Base |
| 04 | [scenario-04-prompt-management](./scenario-04-prompt-management/) | Version and deploy prompt templates with Bedrock Prompt Management |
| 05 | [scenario-05-guardrails](./scenario-05-guardrails/) | Content filtering, PII redaction, and topic denial with Bedrock Guardrails |
| 06 | [scenario-06-governance](./scenario-06-governance/) | Model access controls, CloudTrail audit logging, and Config compliance |
| 07 | [scenario-07-cost-optimization](./scenario-07-cost-optimization/) | Token budgets, cost dashboards, batch inference, and prompt caching |
| 08 | [scenario-08-model-evaluation](./scenario-08-model-evaluation/) | Automatic model evaluation jobs and metric-based model comparison |
| 09 | [scenario-09-troubleshooting](./scenario-09-troubleshooting/) | Reproduce and resolve throttling, permission, and RAG pipeline failures |
| 10 | [scenario-10-cicd](./scenario-10-cicd/) | CodePipeline automating Terraform deploy and model evaluation gating |

Scenarios 02, 03, and 09 depend on scenario-01 infrastructure. The Taskfile handles
this dependency automatically.

---

## Prerequisites

| Tool | Minimum version | Purpose |
|------|----------------|---------|
| AWS account | — | Bedrock model access enabled in `us-east-1` |
| [Terraform](https://developer.hashicorp.com/terraform/install) | 1.7+ | Infrastructure provisioning |
| [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) | 2.x | Auth and credential profiles |
| [Task](https://taskfile.dev/installation/) | 3.x | `Taskfile.yml` task runner |
| [uv](https://docs.astral.sh/uv/getting-started/installation/) | 0.4+ | Python environment for Lambda source code |

Configure credentials before running any scenario:

```bash
aws configure          # or export AWS_PROFILE=<your-profile>
aws bedrock list-foundation-models --region us-east-1   # smoke-test access
```

---

## Using the Taskfile

Install [Task](https://taskfile.dev/installation/) then run all tasks from the **repo root**.

```bash
# Validate shared Terraform modules
task shared:up

# Deploy a single scenario  (terraform init + apply)
task scenario-01:up

# Preview changes without applying
task scenario-02:plan       # auto-deploys scenario-01 first if state is absent

# Tear down a scenario
task scenario-03:down
```

Available tasks follow the pattern `scenario-NN:{plan,up,down}` for each of the ten
scenarios. Scenarios 02, 03, and 09 check for scenario-01 state before running and
deploy it automatically if it is absent.

---

## Shared Terraform modules

Reusable modules live in `modules/` and are consumed via local `module` blocks inside
each scenario's `main.tf`.

| Module | What it provides |
|--------|-----------------|
| `modules/vpc` | VPC, public/private subnets, NAT gateway |
| `modules/iam_roles` | Lambda execution role with Bedrock `InvokeModel` permission |
| `modules/s3` | Versioned, encrypted S3 bucket with public-access block |
| `modules/lambda_base` | Zipped Lambda function, CloudWatch log group, and IAM wiring |

---

## Data directory

`data/` holds sample corpus documents and evaluation datasets referenced by scenario
README files. Add plain-text, PDF, or Markdown files here to use as a RAG corpus in
scenarios 02 and 03.

---

## Scenario README structure

Each scenario folder contains a `README.md` with four sections:

- **Goal** — what you will build and why it matters for the exam
- **Infrastructure deployed** — table of AWS resources and their purpose
- **Key concepts** — exam-relevant terminology and mental models
- **What to observe** — specific things to watch for once the scenario is running

---

## State management

All scenarios use **local Terraform state** (the default). State files are `.gitignore`d
and remain on your workstation. For a shared or persistent lab environment, swap the
backend block in each scenario's `main.tf` to S3 + DynamoDB locking.

---

## License

MIT — see [LICENSE](./LICENSE).
