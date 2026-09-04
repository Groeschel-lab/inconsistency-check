"""FastAPI backend for detecting internal inconsistencies in clinical text."""
from __future__ import annotations

import json
import logging
import os
import re

import requests
from azure.identity import DefaultAzureCredential
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

# Load local settings when python-dotenv is installed.
try:
    from dotenv import load_dotenv

    load_dotenv(os.path.join(os.path.dirname(__file__), ".env"))
except ImportError:
    pass

ENDPOINT = os.environ.get("AZURE_AI_ENDPOINT", os.environ.get("AZURE_OPENAI_ENDPOINT", "")).rstrip("/")
DEPLOYMENT = os.environ.get("AZURE_AI_DEPLOYMENT", os.environ.get("AZURE_OPENAI_DEPLOYMENT", ""))
MODEL_FORMAT = os.environ.get("MODEL_FORMAT", "OpenAI")  # Anthropic uses /anthropic/v1/messages.
INSTITUTION_NAME = os.environ.get("INSTITUTION_NAME", "").strip()
ALLOWED_ORIGINS = [o for o in os.environ.get("ALLOWED_ORIGINS", "*").split(",") if o] or ["*"]
TOKEN_SCOPE = "https://ai.azure.com/.default"  # Azure AI Foundry inference.
MAX_TOKENS = int(os.environ.get("MAX_COMPLETION_TOKENS", "8000"))
REQUEST_TIMEOUT = 180
LOGGER = logging.getLogger(__name__)

_DEFAULT_SYSTEM_PROMPT = """ROLE: Du bist ein System zur Erkennung logischer Unstimmigkeiten in Arztbriefen, um die Qualität zu verbessern.

AUFGABE: Analysiere den folgenden Arztbrief ausschliesslich auf interne logische Unstimmigkeiten (Widersprüche, zeitliche Inkonsistenzen, widersprüchliche Angaben). Es geht nicht um stilistische oder formale Aspekte. Es geht vor allem um offensichtliche Unstimmigkeiten, die auch von Fachfremden gefunden werden könnten.

VORGEHEN:
1. Lies den Arztbrief sorgfältig und vollständig.
2. Identifiziere alle Stellen, an denen sich der Brief intern widerspricht.
3. Wende strenge logische Analyse (Aussagenlogik) auf den vorliegenden Text an. Du solltest kein medizinisches Wissen oder Leitlinien benötigen.

KATEGORIEN (genau eine pro Unstimmigkeit): Inhalt, Zeitlich, Struktur, Sprachlich, Sonstige.
Es ist ausdrücklich NICHT erforderlich, in jeder Kategorie eine Unstimmigkeit zu finden. Viele Arztbriefe enthalten keine oder nur in einzelnen Kategorien Unstimmigkeiten. Erfinde keine Befunde, nur um Kategorien zu füllen.

SCHWEREGRAD (1-9): 1-3 geringfügig ohne klinische Konsequenz; 4-6 relevanter Widerspruch mit potentieller Auswirkung; 7-9 schwerwiegend mit klinischer Relevanz (9 nur eindeutig kritisch). Sei konservativ.

REGELN:
- Nur eindeutige, signifikante Unstimmigkeiten auflisten; unsichere/triviale weglassen.
- Für jede Unstimmigkeit relevante Textstellen zitieren, Korrekturvorschlag und klinische Auswirkung angeben.

Antworte ausschliesslich als JSON-Objekt exakt in dieser Form:
{"issues": [{"description": str, "context": str, "category": "Inhalt|Zeitlich|Struktur|Sprachlich|Sonstige", "severity": 1-9, "rationale": str, "clinical_impact": str, "correction": str}]}
Wenn keine Unstimmigkeit vorliegt, gib {"issues": []} zurück."""

SYSTEM_PROMPT = os.environ.get("SYSTEM_PROMPT") or _DEFAULT_SYSTEM_PROMPT

_credential = DefaultAzureCredential()


def _bearer_token() -> str:
    return _credential.get_token(TOKEN_SCOPE).token


def _extract_issues(content: str) -> list[dict]:
    content = (content or "").strip()
    if not content:
        return []
    try:
        parsed = json.loads(content)
    except json.JSONDecodeError:
        match = re.search(r"\{.*\}", content, re.S)
        if not match:
            return []
        parsed = json.loads(match.group(0))
    if isinstance(parsed, dict):
        return parsed.get("issues") or []
    return parsed if isinstance(parsed, list) else []


app = FastAPI(title="Inconsistency Check", version="1.0.0")
app.add_middleware(
    CORSMiddleware, allow_origins=ALLOWED_ORIGINS,
    allow_methods=["*"], allow_headers=["*"],
)


class AnalyzeRequest(BaseModel):
    text: str


@app.get("/api/health")
def health() -> dict:
    return {"status": "ok", "deployment": DEPLOYMENT, "format": MODEL_FORMAT,
            "institution": INSTITUTION_NAME,
            "endpoint_configured": bool(ENDPOINT)}


def _call_openai(headers: dict, text: str) -> str:
    body = {
        "model": DEPLOYMENT,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": text},
        ],
        "response_format": {"type": "json_object"},
    }
    resp = requests.post(f"{ENDPOINT}/openai/v1/chat/completions", headers=headers,
                         json=body, timeout=REQUEST_TIMEOUT)
    if resp.status_code >= 400:
        LOGGER.warning("Model request failed: route=openai status=%s", resp.status_code)
        raise HTTPException(502, f"model call failed ({resp.status_code})")
    return ((resp.json().get("choices") or [{}])[0].get("message") or {}).get("content", "")


def _call_anthropic(headers: dict, text: str) -> str:
    body = {
        "model": DEPLOYMENT,
        "max_tokens": MAX_TOKENS,
        "system": SYSTEM_PROMPT,
        "messages": [{"role": "user", "content": text}],
    }
    resp = requests.post(f"{ENDPOINT}/anthropic/v1/messages",
                         headers={**headers, "anthropic-version": "2023-06-01"},
                         json=body, timeout=REQUEST_TIMEOUT)
    if resp.status_code >= 400:
        LOGGER.warning("Model request failed: route=anthropic status=%s", resp.status_code)
        raise HTTPException(502, f"model call failed ({resp.status_code})")
    return "".join(p.get("text", "") for p in (resp.json().get("content") or []) if isinstance(p, dict))


@app.post("/api/analyze")
def analyze(req: AnalyzeRequest) -> dict:
    if not ENDPOINT or not DEPLOYMENT:
        LOGGER.error("Model endpoint or deployment is not configured")
        raise HTTPException(500, "AZURE_AI_ENDPOINT / AZURE_AI_DEPLOYMENT not configured")
    text = (req.text or "").strip()
    if not text:
        raise HTTPException(400, "empty text")
    headers = {"Authorization": f"Bearer {_bearer_token()}", "Content-Type": "application/json"}
    try:
        content = (_call_anthropic if MODEL_FORMAT.lower() == "anthropic" else _call_openai)(headers, text)
    except requests.RequestException as exc:
        LOGGER.warning("Model request failed: exception=%s", exc.__class__.__name__)
        raise HTTPException(502, f"model call failed: {exc.__class__.__name__}")
    return {"issues": _extract_issues(content)}


_FRONTEND = os.path.join(os.path.dirname(__file__), "..", "frontend")
if os.path.isdir(_FRONTEND):
    app.mount("/", StaticFiles(directory=_FRONTEND, html=True), name="frontend")
