"""Comprehend pre-processing guard shared by the RAG query scripts.

Runs before any retrieval or FM call: checks sentiment and dominant language
(informational — logged as warnings, never block the request) and PII
(blocks the request outright, since PII shouldn't reach an FM or get embedded
and stored in the vector index).
"""
from dataclasses import dataclass

NEGATIVE_SENTIMENT_THRESHOLD = 0.9
LANGUAGE_CODE = "en"


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
