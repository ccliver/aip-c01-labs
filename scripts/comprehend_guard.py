"""Comprehend pre-processing guard and response post-validation shared by the
RAG query scripts.

check_input() runs before any retrieval or FM call: checks sentiment and
dominant language (informational — logged as warnings, never block the
request) and PII (blocks the request outright, since PII shouldn't reach an
FM or get embedded and stored in the vector index).

validate_response() runs after the FM generates an answer but before it's
returned to the user: flags (never blocks) responses that look low-confidence
— too short, hedging language, or no lexical overlap with the top retrieved
chunk — logs the flag to CloudWatch, and appends a disclaimer.
"""
import json
import re
import time
from dataclasses import dataclass

NEGATIVE_SENTIMENT_THRESHOLD = 0.9
LANGUAGE_CODE = "en"

MIN_RESPONSE_LENGTH = 50
UNCERTAINTY_PHRASES = [
    "i don't know",
    "i'm not sure",
    "i cannot find",
    "no information available",
]
LOG_GROUP_NAME = "/aip-c01-labs/rag-response-validation"
DISCLAIMER = "\n\n[Note: this response may be low-confidence — please verify against official AWS documentation.]"

# Small function-word list for the term-overlap check below — good enough to
# filter out matches on "which"/"there"/etc, not meant to be exhaustive.
_STOPWORDS = {
    "the", "a", "an", "and", "or", "but", "is", "are", "was", "were", "be", "been",
    "being", "to", "of", "in", "on", "at", "by", "for", "with", "about", "as", "into",
    "like", "through", "after", "over", "between", "out", "against", "during", "without",
    "before", "under", "around", "among", "this", "that", "these", "those", "it", "its",
    "you", "your", "can", "will", "would", "should", "could", "may", "might", "must",
    "not", "no", "do", "does", "did", "has", "have", "had", "what", "which", "who",
    "when", "where", "why", "how", "if", "than", "then", "so", "such", "also", "there",
}


@dataclass
class ComprehendCheck:
    sentiment: str
    sentiment_score: float
    language_code: str
    language_score: float
    pii_entity_types: list[str]

    @property
    def blocked(self) -> bool:
        return bool(self.pii_entity_types)

    @property
    def warnings(self) -> list[str]:
        warnings = []
        if self.sentiment == "NEGATIVE" and self.sentiment_score > NEGATIVE_SENTIMENT_THRESHOLD:
            warnings.append(f"negative sentiment (score={self.sentiment_score:.3f})")
        if self.language_code != LANGUAGE_CODE:
            warnings.append(f"non-English input detected (language={self.language_code}, score={self.language_score:.3f})")
        return warnings


def check_input(comprehend, text: str) -> ComprehendCheck:
    sentiment_resp = comprehend.detect_sentiment(Text=text, LanguageCode=LANGUAGE_CODE)
    sentiment = sentiment_resp["Sentiment"]
    sentiment_score = sentiment_resp["SentimentScore"][sentiment.capitalize()]

    languages = comprehend.detect_dominant_language(Text=text)["Languages"]
    top_language = max(languages, key=lambda l: l["Score"]) if languages else {"LanguageCode": "unknown", "Score": 0.0}

    pii_entities = comprehend.detect_pii_entities(Text=text, LanguageCode=LANGUAGE_CODE)["Entities"]

    return ComprehendCheck(
        sentiment=sentiment,
        sentiment_score=sentiment_score,
        language_code=top_language["LanguageCode"],
        language_score=top_language["Score"],
        pii_entity_types=sorted({e["Type"] for e in pii_entities}),
    )


@dataclass
class ResponseValidation:
    low_confidence: bool
    reasons: list[str]
    response: str  # original response, with DISCLAIMER appended if low_confidence


def _significant_terms(text: str) -> set[str]:
    words = re.findall(r"[a-z]+", text.lower())
    return {w for w in words if len(w) > 4 and w not in _STOPWORDS}


def _log_flags(logs, question: str, response: str, reasons: list[str]) -> None:
    log_stream = time.strftime("%Y-%m-%d")
    try:
        logs.create_log_group(logGroupName=LOG_GROUP_NAME)
    except logs.exceptions.ResourceAlreadyExistsException:
        pass
    try:
        logs.create_log_stream(logGroupName=LOG_GROUP_NAME, logStreamName=log_stream)
    except logs.exceptions.ResourceAlreadyExistsException:
        pass

    message = json.dumps({"question": question, "response": response, "reasons": reasons})
    logs.put_log_events(
        logGroupName=LOG_GROUP_NAME,
        logStreamName=log_stream,
        logEvents=[{"timestamp": int(time.time() * 1000), "message": message}],
    )


def validate_response(logs, question: str, response: str, chunks: list[str]) -> ResponseValidation:
    reasons = []

    if len(response) < MIN_RESPONSE_LENGTH:
        reasons.append(f"response is short ({len(response)} chars < {MIN_RESPONSE_LENGTH})")

    lowered = response.lower()
    matched_phrases = [p for p in UNCERTAINTY_PHRASES if p in lowered]
    if matched_phrases:
        reasons.append(f"uncertainty language detected: {', '.join(matched_phrases)}")

    if chunks:
        top_chunk_terms = _significant_terms(chunks[0])
        if top_chunk_terms and not (top_chunk_terms & _significant_terms(response)):
            reasons.append("response shares no significant terms with the top retrieved chunk (possible hallucination)")

    low_confidence = bool(reasons)
    if low_confidence:
        _log_flags(logs, question, response, reasons)

    return ResponseValidation(
        low_confidence=low_confidence,
        reasons=reasons,
        response=response + DISCLAIMER if low_confidence else response,
    )
