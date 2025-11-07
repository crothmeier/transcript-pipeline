import os
import json
import re
from typing import List, Optional
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from openai import OpenAI
from anthropic import Anthropic
from prometheus_fastapi_instrumentator import Instrumentator

app = FastAPI(title="Transcript Classifier")

LOCAL_VLLM_BASE = os.getenv("LOCAL_VLLM_BASE", "")
LOCAL_MODEL = os.getenv("LOCAL_MODEL", "Qwen/Qwen2.5-14B-Instruct-AWQ")
ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY", "")
USE_LOCAL_FIRST = os.getenv("USE_LOCAL_FIRST", "true").lower() == "true"

local_client = None
anthropic_client = None

if LOCAL_VLLM_BASE:
    local_client = OpenAI(base_url=LOCAL_VLLM_BASE, api_key="dummy")

if ANTHROPIC_API_KEY:
    anthropic_client = Anthropic(api_key=ANTHROPIC_API_KEY)

SYSTEM_PROMPT = """You are a transcript classifier. Analyze the provided text and return ONLY valid JSON with this exact structure:
{
    "tags": ["tag1", "tag2", "tag3"],
    "summary": "A comprehensive summary of 150-200 words...",
    "confidence": 0.85
}

Requirements:
- tags: Array of 3-7 descriptive labels/categories
- summary: Detailed summary between 150-200 words
- confidence: Float between 0.0 and 1.0 indicating classification confidence
- Return ONLY the JSON, no additional text or markdown formatting"""


class ClassifyRequest(BaseModel):
    text: str
    source: Optional[str] = None
    filepath: Optional[str] = None
    force_local: bool = False
    force_api: bool = False


class ClassifyResponse(BaseModel):
    tags: List[str]
    summary: str
    confidence: float
    model: str
    fallback_used: bool


def parse_json_response(text: str) -> dict:
    """Parse JSON from response, handling markdown code blocks"""
    text = text.strip()

    json_match = re.search(r'```(?:json)?\s*(\{.*?\})\s*```', text, re.DOTALL)
    if json_match:
        text = json_match.group(1)

    text = re.sub(r'^```(?:json)?\s*', '', text)
    text = re.sub(r'\s*```$', '', text)

    try:
        return json.loads(text)
    except json.JSONDecodeError as e:
        raise ValueError(f"Failed to parse JSON: {e}")


def heuristic_fallback(text: str) -> dict:
    """Simple heuristic fallback when all models fail"""
    words = text.split()
    word_count = len(words)

    tags = ["uncategorized", "transcript", "unclassified"]

    if word_count < 100:
        tags.append("short")
    elif word_count > 1000:
        tags.append("long")

    summary = " ".join(words[:min(50, word_count)])
    if word_count > 50:
        summary += "..."

    return {
        "tags": tags[:7],
        "summary": summary,
        "confidence": 0.3
    }


def classify_with_local(text: str) -> dict:
    """Classify using local vLLM model"""
    if not local_client:
        raise RuntimeError("Local vLLM not configured")

    response = local_client.chat.completions.create(
        model=LOCAL_MODEL,
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": f"Classify this transcript:\n\n{text[:4000]}"}
        ],
        temperature=0.7,
        max_tokens=1000
    )

    content = response.choices[0].message.content
    result = parse_json_response(content)

    result.setdefault("tags", [])
    result.setdefault("summary", "")
    result.setdefault("confidence", 0.5)

    return result


def classify_with_api(text: str) -> dict:
    """Classify using Anthropic API"""
    if not anthropic_client:
        raise RuntimeError("Anthropic API not configured")

    message = anthropic_client.messages.create(
        model="claude-3-5-sonnet-20241022",
        max_tokens=1000,
        system=SYSTEM_PROMPT,
        messages=[
            {"role": "user", "content": f"Classify this transcript:\n\n{text[:4000]}"}
        ]
    )

    content = message.content[0].text
    result = parse_json_response(content)

    result.setdefault("tags", [])
    result.setdefault("summary", "")
    result.setdefault("confidence", 0.5)

    return result


@app.get("/health")
async def health():
    """Health check endpoint"""
    local_configured = LOCAL_VLLM_BASE != ""
    api_configured = ANTHROPIC_API_KEY != ""

    models = []
    if local_configured:
        models.append(LOCAL_MODEL)
    if api_configured:
        models.append("claude-3-5-sonnet-20241022")

    return {
        "status": "healthy",
        "local_configured": local_configured,
        "api_configured": api_configured,
        "models": models
    }


@app.post("/classify", response_model=ClassifyResponse)
async def classify(request: ClassifyRequest):
    """Classify transcript text"""
    if not request.text or not request.text.strip():
        raise HTTPException(status_code=400, detail="Text cannot be empty")

    fallback_used = False
    model_used = "none"
    result = None

    try:
        if request.force_api:
            result = classify_with_api(request.text)
            model_used = "claude-3-5-sonnet-20241022"
        elif request.force_local:
            result = classify_with_local(request.text)
            model_used = LOCAL_MODEL
        elif USE_LOCAL_FIRST and local_client:
            try:
                result = classify_with_local(request.text)
                model_used = LOCAL_MODEL

                if result["confidence"] < 0.7 and anthropic_client:
                    result = classify_with_api(request.text)
                    model_used = "claude-3-5-sonnet-20241022"
                    fallback_used = True
            except Exception as e:
                if anthropic_client:
                    result = classify_with_api(request.text)
                    model_used = "claude-3-5-sonnet-20241022"
                    fallback_used = True
                else:
                    raise
        elif anthropic_client:
            result = classify_with_api(request.text)
            model_used = "claude-3-5-sonnet-20241022"
        else:
            raise HTTPException(
                status_code=503,
                detail="No classification backend configured"
            )
    except Exception as e:
        result = heuristic_fallback(request.text)
        model_used = "heuristic"
        fallback_used = True

    return ClassifyResponse(
        tags=result["tags"],
        summary=result["summary"],
        confidence=result["confidence"],
        model=model_used,
        fallback_used=fallback_used
    )


Instrumentator().instrument(app).expose(app)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8081)
