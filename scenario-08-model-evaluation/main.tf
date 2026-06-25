# TODO: module "eval_bucket" — call modules/s3 for evaluation dataset and results
# TODO: aws_s3_object — upload sample dataset JSONL from data/ to eval_bucket
# TODO: module "iam" — call modules/iam_roles; add bedrock:CreateEvaluationJob + S3 permissions
# Note: aws_bedrock_evaluation_job may not yet exist in the provider; use null_resource + CLI
# TODO: null_resource — trigger: aws bedrock create-evaluation-job --cli-input-json file://eval_job.json
