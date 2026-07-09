#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = ["boto3", "opensearch-py", "requests-aws4auth"]
# ///
import os
import sys
import boto3
from opensearchpy import OpenSearch, RequestsHttpConnection
from requests_aws4auth import AWS4Auth

ENDPOINT = os.environ["OS_ENDPOINT"]
INDEX = os.environ["OS_INDEX"]
REGION = os.environ.get("AWS_REGION", "us-east-1")

session = boto3.Session()
creds = session.get_credentials().get_frozen_credentials()
auth = AWS4Auth(creds.access_key, creds.secret_key, REGION, "aoss", session_token=creds.token)

client = OpenSearch(
    hosts=[{"host": ENDPOINT, "port": 443}],
    http_auth=auth,
    use_ssl=True,
    verify_certs=True,
    connection_class=RequestsHttpConnection,
)

if client.indices.exists(index=INDEX):
    print(f"Index '{INDEX}' already exists, skipping creation")
    sys.exit(0)

client.indices.create(index=INDEX, body={
    "settings": {"index": {"knn": True}},
    "mappings": {"properties": {
        "bedrock-knowledge-base-default-vector": {"type": "knn_vector", "dimension": 1024, "method": {"name": "hnsw", "engine": "faiss"}},
        "AMAZON_BEDROCK_TEXT_CHUNK": {"type": "text"},
        "AMAZON_BEDROCK_METADATA": {"type": "text"},
    }},
})
print(f"Created index '{INDEX}'")
