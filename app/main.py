# type: ignore
from __future__ import annotations

import os
from typing import Dict

import boto3
import cohere
from fastapi import FastAPI, HTTPException
from fastapi.responses import HTMLResponse
from mypy_boto3_secretsmanager.client import SecretsManagerClient
from pydantic import BaseModel, Field

###############################################################################
# Configuration helpers
###############################################################################

SECRET_NAME: str = os.getenv("SECRET_NAME", "CohereApiKeyV5")
AWS_REGION: str = os.getenv("AWS_REGION", "us-east-1")

app = FastAPI(title="Cohere Privacy Gateway", version="0.2.0")

###############################################################################
# Data models (strict typing with Pydantic)
###############################################################################

class SummarizeRequest(BaseModel):
    """Input payload for /summarize."""

    raw_text: str = str, Field(..., min_length=1, example="Customer John Doe needs help.")

class SummarizeResponse(BaseModel):
    """Response payload for /summarize."""

    summary: str
    original_word_count: int

###############################################################################
# Cohere client (lazy singleton)
###############################################################################

_cohere: cohere.Client | None = None  # cached client

def _fetch_secret_from_aws() -> str:
    """Retrieve the Cohere API key from AWS Secrets Manager (one network call).

    Raises HTTPException if the secret cannot be fetched.
    """
    try:
        sm: SecretsManagerClient = boto3.client("secretsmanager", region_name=AWS_REGION)
        response = sm.get_secret_value(SecretId=SECRET_NAME)
        secret = response.get("SecretString")
        if not secret:
            raise ValueError("SecretString is empty in Secrets Manager response")
        return secret
    except Exception as exc:  # noqa: BLE001  # broad but we map to HTTP 500
        print(f"[WARN] Could not fetch secret — falling back to env var: {exc}")
        env_key = os.getenv("COHERE_API_KEY")
        if env_key:
            return env_key
        raise HTTPException(status_code=500, detail="Cohere API key unavailable.")

def get_cohere_client() -> cohere.Client:
    """Return a cached Cohere client instance (creates on first call)."""
    global _cohere
    if _cohere is None:
        _cohere = cohere.Client(_fetch_secret_from_aws())
    return _cohere

###############################################################################
# Routes
###############################################################################

@app.get("/", response_class=HTMLResponse)
def root() -> HTMLResponse:
    return HTMLResponse(
        """
        <h2>Cohere Privacy Gateway</h2>
        <p>→ <a href="/docs">Swagger UI</a></p>
        <p>→ <a href="/health">Health Check</a></p>
        """,
        status_code=200,
    )

@app.get("/health", tags=["meta"])
async def health_check() -> Dict[str, str]:
    """Health‑check route for load‑balancers/monitoring."""
    return {"status": "ok"}

@app.post("/summarize", response_model=SummarizeResponse, tags=["nlp"])
async def summarize(request: SummarizeRequest) -> SummarizeResponse:  # noqa: D401
    """Summarize raw customer text using Cohere’s command‑r‑plus model."""

    text: str = request.raw_text
    word_count: int = len(text.split())

    MIN_CHARS = 250

    if len(text) < MIN_CHARS:
        raise HTTPException(
            status_code=400,
            detail=f"Input text must be at least {MIN_CHARS} characters."
        )

    try:
        response = get_cohere_client().summarize(
            text=text,
            model="command-r-plus",
            length="short",
            format="paragraph",
        )
        return SummarizeResponse(summary=response.summary, original_word_count=word_count)
    except Exception as exc:  # noqa: BLE001  # handle any Cohere failure
        print(f"[ERROR] Cohere summarize failed: {exc}")
        raise HTTPException(status_code=502, detail="Failed to summarize via Cohere.") from exc
