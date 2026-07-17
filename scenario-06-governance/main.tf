# TODO: aws_cloudtrail — trail capturing all bedrock:* management events
# TODO: aws_s3_bucket + aws_s3_bucket_policy — CloudTrail log destination
# TODO: aws_iam_policy — deny bedrock:InvokeModel except for approved model IDs
# TODO: aws_config_rule — detect Bedrock resources missing required tags

# NOTE: aws_bedrock_model_invocation_logging_configuration is deployed by
# scenario-04-prompt-management, not here — it's an account+region-wide
# singleton, so only one scenario can own it. See its README for the CWL/S3
# destinations it configures. scenario-04 must stay deployed for data-plane
# invocation logging to be active in this account/region.
