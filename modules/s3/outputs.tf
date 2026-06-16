output "bucket_id" {
  description = "Name of the created S3 bucket"
  value       = null # TODO: replace with aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the created S3 bucket"
  value       = null # TODO: replace with aws_s3_bucket.this.arn
}
