import json
import os
import time
from datetime import datetime, timezone
import boto3
from aws_lambda_powertools import Logger
from aws_lambda_powertools.utilities.typing import LambdaContext
from botocore.config import Config
from opensearchpy import OpenSearch, RequestsHttpConnection
from requests_aws4auth import AWS4Auth

logger = Logger()

bedrock = boto3.client(
    "bedrock-runtime",
    config=Config(retries={"max_attempts": 10, "mode": "adaptive"}),
)

EMBEDDING_MODEL_ID = os.environ["EMBEDDING_MODEL_ID"]
OS_ENDPOINT = os.environ["OS_ENDPOINT"]
OS_INDEX = os.environ["OS_INDEX"]
EMBED_DIMENSIONS = 1024
EMBED_CALL_DELAY_SECONDS = float(os.environ.get("EMBED_CALL_DELAY_SECONDS", "0"))


def get_os_client() -> OpenSearch:
    session = boto3.Session()
    creds = session.get_credentials().get_frozen_credentials()
    region = session.region_name
    auth = AWS4Auth(creds.access_key, creds.secret_key, region, "aoss", session_token=creds.token)
    return OpenSearch(
        hosts=[{"host": OS_ENDPOINT, "port": 443}],
        http_auth=auth,
        use_ssl=True,
        verify_certs=True,
        connection_class=RequestsHttpConnection,
        timeout=60,
        max_retries=3,
        retry_on_timeout=True,
    )


def embed_text(text: str) -> list[float]:
    response = bedrock.invoke_model(
        modelId=EMBEDDING_MODEL_ID,
        body=json.dumps({"inputText": text, "dimensions": EMBED_DIMENSIONS, "normalize": True}),
    )
    time.sleep(EMBED_CALL_DELAY_SECONDS)
    return json.loads(response["body"].read())["embedding"]


def index_documents(os_client: OpenSearch, source_key: str, chunk_offset: int, chunks: list[str], embeddings: list[list[float]]) -> None:
    timestamp = datetime.now(timezone.utc).isoformat()
    actions = []
    for i, (chunk, embedding) in enumerate(zip(chunks, embeddings)):
        actions.append({"index": {"_index": OS_INDEX}})
        actions.append({
            "chunk_id": chunk_offset + i,
            "source_key": source_key,
            "text": chunk,
            "embedding": embedding,
            "domain": "aws-documentation",
            "timestamp": timestamp,
        })
    response = os_client.bulk(body=actions)
    if response.get("errors"):
        failed = [item for item in response["items"] if "error" in item.get("index", {})]
        raise RuntimeError(f"{len(failed)} bulk index error(s): {failed[0]['index']['error']}")


def process_message(body: dict) -> dict:
    source_key = body["source_key"]
    chunk_offset = body["chunk_offset"]
    chunks = body["chunks"]

    logger.info("Embedding batch", extra={"source_key": source_key, "chunk_offset": chunk_offset, "batch_size": len(chunks)})

    embeddings = [embed_text(chunk) for chunk in chunks]

    os_client = get_os_client()
    index_documents(os_client, source_key, chunk_offset, chunks, embeddings)

    logger.info("Indexed batch", extra={"source_key": source_key, "chunk_offset": chunk_offset, "indexed": len(chunks)})
    return {"source_key": source_key, "chunk_offset": chunk_offset, "indexed": len(chunks)}


@logger.inject_lambda_context
def handler(event: dict, context: LambdaContext) -> dict:
    results = []
    failed = []

    for record in event.get("Records", []):
        message_id = record.get("messageId")
        try:
            body = json.loads(record["body"])
            result = process_message(body)
            results.append(result)
        except Exception:
            logger.exception("Failed to process SQS record", extra={"message_id": message_id})
            failed.append(message_id)

    if failed:
        raise RuntimeError(f"Failed to process {len(failed)} SQS record(s): {failed}")

    return {"statusCode": 200, "processed": results}
