FROM docker.io/python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    git build-essential curl && rm -rf /var/lib/apt/lists/*

# Torch with CUDA support (>= 2.6 required for CVE-2025-32434 fix)
RUN python -m pip install --upgrade pip && \
    pip install torch==2.6.0

# Minimal requirements - let packages pull dependencies
RUN pip install \
    fastapi \
    uvicorn[standard] \
    pydantic \
    prometheus-fastapi-instrumentator \
    FlagEmbedding>=1.2.10

WORKDIR /app
COPY embeddings.py /app/embeddings.py

EXPOSE 8080

USER 1000

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

CMD ["uvicorn", "embeddings:app", "--host", "0.0.0.0", "--port", "8080"]
