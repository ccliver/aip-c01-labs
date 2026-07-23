resource "aws_bedrock_guardrail" "this" {
  name                      = "${var.project}-guardrail"
  blocked_input_messaging   = "This input was blocked by content safety guardrails."
  blocked_outputs_messaging = "This response was blocked by content safety guardrails."

  content_policy_config {
    dynamic "filters_config" {
      for_each = toset(["HATE", "VIOLENCE", "SEXUAL", "INSULTS"])
      content {
        type            = filters_config.value
        input_strength  = var.content_filter_strength
        output_strength = var.content_filter_strength
        input_enabled   = true
        output_enabled  = true
      }
    }

    # Jailbreaks/prompt injection only ever show up in what the user sends,
    # so this filter has no output_strength/output_enabled — unlike the
    # categories above, it isn't evaluated against model responses.
    filters_config {
      type            = "PROMPT_ATTACK"
      input_strength  = var.content_filter_strength
      output_strength = "NONE"
      input_enabled   = true
      output_enabled  = false
    }
  }

  topic_policy_config {
    topics_config {
      name       = var.denied_topic_name
      type       = "DENY"
      definition = var.denied_topic_definition
      examples   = var.denied_topic_examples
    }
  }

  word_policy_config {
    dynamic "words_config" {
      for_each = var.blocked_words
      content {
        text = words_config.value
      }
    }
  }

  sensitive_information_policy_config {
    dynamic "pii_entities_config" {
      for_each = var.pii_entity_types
      content {
        type   = pii_entities_config.value
        action = var.pii_action
      }
    }
  }

  contextual_grounding_policy_config {
    filters_config {
      type      = "GROUNDING"
      threshold = var.grounding_threshold
    }
  }
}

# Pinned numbered version so consumers reference a stable snapshot rather than
# the mutable DRAFT — the guardrail's policies can keep evolving after this.
# replace_triggered_by forces a new version whenever the guardrail's policy
# config changes (updated_at bumps), since the AWS provider has no way to
# create a new version in place — otherwise this pinned version would silently
# drift out of sync with the draft.
resource "aws_bedrock_guardrail_version" "this" {
  guardrail_arn = aws_bedrock_guardrail.this.guardrail_arn
  description   = "Pinned version"

  lifecycle {
    replace_triggered_by = [aws_bedrock_guardrail.this.updated_at]
  }
}

resource "aws_ssm_parameter" "guardrail_id" {
  name  = "/${var.project}/guardrails/id"
  type  = "String"
  value = aws_bedrock_guardrail.this.guardrail_id
}

resource "aws_ssm_parameter" "guardrail_version" {
  name  = "/${var.project}/guardrails/version"
  type  = "String"
  value = aws_bedrock_guardrail_version.this.version
}
