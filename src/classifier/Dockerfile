FROM docker.io/python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

RUN apt-get update && apt-get install -y --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/*

RUN pip install --upgrade pip && \
    pip install \
    fastapi \
    uvicorn[standard] \
    httpx \
    pydantic \
    prometheus-fastapi-instrumentator \
    anthropic \
    openai

WORKDIR /app
COPY classifier.py /app/classifier.py

EXPOSE 8081

USER 1000

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD curl -f http://localhost:8081/health || exit 1

CMD ["uvicorn", "classifier:app", "--host", "0.0.0.0", "--port", "8081"]
