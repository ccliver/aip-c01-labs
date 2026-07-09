#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = ["boto3"]
# ///
import os
import sys
import boto3

KB_ID = os.environ["KB_ID"]
REGION = os.environ.get("AWS_REGION", "us-east-1")
TOP_K = 5

if len(sys.argv) < 2:
    print("Usage: kb_retrieve.py <question>")
    sys.exit(1)

question = " ".join(sys.argv[1:])

session = boto3.Session()
client = session.client("bedrock-agent-runtime", region_name=REGION)

response = client.retrieve(
    knowledgeBaseId=KB_ID,
    retrievalQuery={"text": question},
    retrievalConfiguration={"vectorSearchConfiguration": {"numberOfResults": TOP_K}},
)

results = response.get("retrievalResults", [])
if not results:
    print("No results found.")
    sys.exit(0)

print(f"\nQuery: {question}\n{'─' * 60}")
for i, result in enumerate(results, 1):
    score = result.get("score", 0)
    uri = result.get("location", {}).get("s3Location", {}).get("uri", "unknown")
    source = uri.split("/", 3)[-1] if uri.startswith("s3://") else uri
    print(f"\n[{i}] score={score:.4f}  source={source}")
    print(result["content"]["text"])
    print("─" * 60)
