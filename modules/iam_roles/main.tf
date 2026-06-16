# Shared IAM roles module — reusable execution roles for Lambda and other compute
# resources that need access to Amazon Bedrock.

# TODO: aws_iam_role (lambda_bedrock_exec) with trust policy for lambda.amazonaws.com
# TODO: aws_iam_role_policy_attachment — AWSLambdaBasicExecutionRole managed policy
# TODO: aws_iam_policy — bedrock:InvokeModel, bedrock:InvokeModelWithResponseStream
# TODO: aws_iam_role_policy_attachment — attach Bedrock policy to Lambda role
