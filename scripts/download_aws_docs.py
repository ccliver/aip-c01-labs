#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Download AWS service documentation PDFs for AIP-C01 exam preparation."""

import shutil
import sys
import urllib.request
from pathlib import Path

OUTPUT_DIR = Path(__file__).parent.parent / "data" / "aws-docs"

# (slug, label, pdf_url)
DOCS = [
    (
        "bedrock",
        "Amazon Bedrock User Guide",
        "https://docs.aws.amazon.com/bedrock/latest/userguide/bedrock-ug.pdf",
    ),
    (
        "opensearch",
        "Amazon OpenSearch Service Developer Guide",
        "https://docs.aws.amazon.com/opensearch-service/latest/developerguide/opensearch-service-dg.pdf",
    ),
    (
        "aurora",
        "Amazon Aurora User Guide",
        "https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-ug.pdf",
    ),
    (
        "lambda",
        "AWS Lambda Developer Guide",
        "https://docs.aws.amazon.com/lambda/latest/dg/lambda-dg.pdf",
    ),
    (
        "step-functions",
        "AWS Step Functions Developer Guide",
        "https://docs.aws.amazon.com/step-functions/latest/dg/step-functions-dg.pdf",
    ),
    (
        "cloudwatch",
        "Amazon CloudWatch User Guide",
        "https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/acw-ug.pdf",
    ),
    (
        "athena",
        "Amazon Athena User Guide",
        "https://docs.aws.amazon.com/athena/latest/ug/athena-ug.pdf",
    ),
    (
        "comprehend",
        "Amazon Comprehend Developer Guide",
        "https://docs.aws.amazon.com/comprehend/latest/dg/comprehend-dg.pdf",
    ),
]


def progress_hook(slug: str):
    def _hook(block_count: int, block_size: int, total_size: int):
        if total_size <= 0:
            return
        downloaded = min(block_count * block_size, total_size)
        pct = downloaded * 100 // total_size
        bar = "#" * (pct // 5)
        print(f"\r  [{bar:<20}] {pct:3d}%", end="", flush=True)

    return _hook


def main() -> int:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    url_to_path: dict[str, Path] = {}
    failures: list[str] = []

    for slug, label, url in DOCS:
        dest = OUTPUT_DIR / f"{slug}.pdf"

        if dest.exists():
            print(f"  skip  {slug}.pdf  (already exists)")
            url_to_path.setdefault(url, dest)
            continue

        if url in url_to_path:
            shutil.copy2(url_to_path[url], dest)
            print(f"  copy  {slug}.pdf  (from {url_to_path[url].name})")
            continue

        print(f"  fetch {slug}.pdf")
        print(f"        {label}")
        try:
            urllib.request.urlretrieve(url, dest, reporthook=progress_hook(slug))
            print()
            url_to_path[url] = dest
        except Exception as exc:
            print(f"\n  ERROR: {exc}")
            dest.unlink(missing_ok=True)
            failures.append(slug)

    print(f"\nDone. PDFs saved to {OUTPUT_DIR}/")
    if failures:
        print(f"Failed: {', '.join(failures)}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
