#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = ["boto3", "requests", "requests-aws4auth"]
# ///
import json
import os
import sys
import boto3
import requests
from requests_aws4auth import AWS4Auth

ENDPOINT = os.environ["OS_ENDPOINT"]
INDEX = os.environ["OS_INDEX"]
REGION = os.environ.get("AWS_REGION", "us-east-1")
SIZE = int(sys.argv[1]) if len(sys.argv) > 1 else 1
source_filter = sys.argv[2] if len(sys.argv) > 2 else None

session = boto3.Session(profile_name="lab")
creds = session.get_credentials().get_frozen_credentials()
auth = AWS4Auth(creds.access_key, creds.secret_key, REGION, "aoss", session_token=creds.token)

query = {"term": {"source_key": source_filter}} if source_filter else {"match_all": {}}

response = requests.get(
    f"{ENDPOINT}/{INDEX}/_search",
    auth=auth,
    json={"query": query, "size": SIZE},
)
print(json.dumps(response.json(), indent=2))
