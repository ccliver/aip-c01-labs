import io
import json
import os
import boto3
import fitz
from aws_lambda_powertools import Logger
from aws_lambda_powertools.utilities.typing import LambdaContext
from langchain_text_splitters import RecursiveCharacterTextSplitter

logger = Logger()
s3 = boto3.client("s3")
sqs = boto3.client("sqs")

CHUNK_SIZE = int(os.environ.get("CHUNK_SIZE", 1024))
CHUNK_OVERLAP = int(os.environ.get("CHUNK_OVERLAP", 100))
QUEUE_URL = os.environ["QUEUE_URL"]
SQS_BATCH_SIZE = 100

splitter = RecursiveCharacterTextSplitter(
    chunk_size=CHUNK_SIZE,
    chunk_overlap=CHUNK_OVERLAP,
)


def extract_text(pdf_bytes: bytes) -> str:
    with fitz.open(stream=io.BytesIO(pdf_bytes), filetype="pdf") as doc:
        return "\n".join(page.get_text() for page in doc)


def chunk_text(text: str) -> list[str]:
    return splitter.split_text(text)


def store_chunks(bucket: str, source_key: str, chunks: list[str]) -> str:
    stem = os.path.splitext(os.path.basename(source_key))[0]
    output_key = f"chunks/{stem}.json"
    payload = {
        "source_key": source_key,
        "chunk_size": CHUNK_SIZE,
        "chunk_overlap": CHUNK_OVERLAP,
        "total_chunks": len(chunks),
        "chunks": chunks,
    }
    s3.put_object(
        Bucket=bucket,
        Key=output_key,
        Body=json.dumps(payload, ensure_ascii=False),
        ContentType="application/json",
    )
    return output_key


def send_to_sqs(source_key: str, chunks: list[str]) -> int:
    batches = [chunks[i:i + SQS_BATCH_SIZE] for i in range(0, len(chunks), SQS_BATCH_SIZE)]
    messages_sent = 0
    # send_message_batch accepts up to 10 entries per API call
    for api_offset in range(0, len(batches), 10):
        api_batch = batches[api_offset:api_offset + 10]
        entries = [
            {
                "Id": str(api_offset + j),
                "MessageBody": json.dumps({
                    "source_key": source_key,
                    "chunk_offset": (api_offset + j) * SQS_BATCH_SIZE,
                    "chunks": batch,
                }),
            }
            for j, batch in enumerate(api_batch)
        ]
        response = sqs.send_message_batch(QueueUrl=QUEUE_URL, Entries=entries)
        if response.get("Failed"):
            raise RuntimeError(f"SQS send_message_batch had failures: {response['Failed']}")
        messages_sent += len(entries)
    return messages_sent


def process_record(bucket: str, key: str) -> dict:
    logger.info("Processing PDF", extra={"bucket": bucket, "key": key})

    pdf_bytes = s3.get_object(Bucket=bucket, Key=key)["Body"].read()
    text = extract_text(pdf_bytes)
    if not text.strip():
        logger.warning("No extractable text", extra={"bucket": bucket, "key": key})

    chunks = chunk_text(text)
    logger.info("Chunked", extra={"total_chunks": len(chunks), "chunk_size": CHUNK_SIZE, "chunk_overlap": CHUNK_OVERLAP})

    output_key = store_chunks(bucket, key, chunks)
    logger.info("Stored chunks", extra={"output_key": output_key})

    messages_sent = send_to_sqs(key, chunks)
    logger.info("Queued for embedding", extra={"messages_sent": messages_sent, "total_chunks": len(chunks)})

    return {"key": key, "output_key": output_key, "total_chunks": len(chunks), "messages_sent": messages_sent}


@logger.inject_lambda_context
def handler(event: dict, context: LambdaContext) -> dict:
    succeeded = []
    failed = []

    for record in event.get("Records", []):
        bucket = record["s3"]["bucket"]["name"]
        key = record["s3"]["object"]["key"]
        try:
            result = process_record(bucket, key)
            succeeded.append(result)
        except Exception:
            logger.exception("Failed to process PDF", extra={"bucket": bucket, "key": key})
            failed.append(key)

    if failed:
        raise RuntimeError(f"Failed to process {len(failed)} record(s): {failed}")

    return {"statusCode": 200, "processed": succeeded}
