"""Shared CloudWatch custom-metrics helper for the CLI scripts under AIP-C01/Lab.

Scenario-04 (prompt invocations) and scenario-05 (guardrail evaluations) have no
deployed Lambda to instrument — these calls only happen from CLI scripts run via
the Taskfile, so metrics are emitted here via put_metric_data instead of EMF.
"""
import boto3

NAMESPACE = "AIP-C01/Lab"

_cloudwatch = boto3.client("cloudwatch")


def put_metric(name: str, value: float, dimensions: dict, unit: str = "Count") -> None:
    _cloudwatch.put_metric_data(
        Namespace=NAMESPACE,
        MetricData=[{
            "MetricName": name,
            "Dimensions": [{"Name": k, "Value": v} for k, v in dimensions.items()],
            "Value": value,
            "Unit": unit,
        }],
    )


def guardrail_policy_hits(assessments: list) -> list[tuple[str, str]]:
    """Extract (filter_type, detail) pairs for every blocked/anonymized policy hit
    across a list of guardrail assessment dicts. Assessments carry the same shape
    whether read off resp["assessments"] (direct ApplyGuardrail) or
    resp["trace"]["guardrail"]["outputAssessments"][...] (Converse)."""
    hits = []
    for assessment in assessments:
        for topic in assessment.get("topicPolicy", {}).get("topics", []):
            if topic["action"] == "BLOCKED":
                hits.append(("topicPolicy", topic["name"]))
        for f in assessment.get("contentPolicy", {}).get("filters", []):
            if f["action"] == "BLOCKED":
                hits.append(("contentPolicy", f["type"]))
        for w in assessment.get("wordPolicy", {}).get("customWords", []):
            if w["action"] == "BLOCKED":
                hits.append(("wordPolicy", w["match"]))
        for e in assessment.get("sensitiveInformationPolicy", {}).get("piiEntities", []):
            if e["action"] in ("BLOCKED", "ANONYMIZED"):
                hits.append(("piiPolicy", e["type"]))
        for f in assessment.get("contextualGroundingPolicy", {}).get("filters", []):
            if f["action"] == "BLOCKED":
                hits.append(("contextualGroundingPolicy", f"{f['type']}(score={f['score']})"))
    return hits
