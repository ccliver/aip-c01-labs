output "state_machine_arn" {
  description = "ARN of the RAG pipeline Step Functions state machine"
  value       = aws_sfn_state_machine.pipeline.arn
}
