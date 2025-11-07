import os
from typing import List, Optional

import torch
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
from prometheus_fastapi_instrumentator import Instrumentator
from FlagEmbedding import BGEM3FlagModel

class EmbedRequest(BaseModel):
    text: str
    max_length: Optional[int] = None

class EmbedBatchRequest(BaseModel):
    texts: List[str]
    max_length: Optional[int] = Field(default=2048, le=8192)
    batch_size: Optional[int] = Field(default=8, ge=1, le=32)

class EmbedResponse(BaseModel):
    embedding: List[float]
    dim: int = 1024
    model: str

class EmbedBatchResponse(BaseModel):
    embeddings: List[List[float]]
    dim: int = 1024
    model: str

app = FastAPI(title="Embeddings Service", version="0.1.0")
Instrumentator().instrument(app).expose(app)

_model: Optional[BGEM3FlagModel] = None
_model_name = "BAAI/bge-m3"

@app.on_event("startup")
def load_model():
    global _model
    device = "cuda" if torch.cuda.is_available() else "cpu"
    _model = BGEM3FlagModel(_model_name, use_fp16=(device == "cuda"), device=device)

@app.get("/health")
def health():
    return {
        "status": "ok" if _model else "loading",
        "model": _model_name,
        "device": "cuda" if torch.cuda.is_available() else "cpu"
    }

@app.post("/embed", response_model=EmbedResponse)
def embed(req: EmbedRequest):
    if not _model:
        raise HTTPException(status_code=503, detail="model loading")
    try:
        res = _model.encode(
            [req.text],
            batch_size=1,
            max_length=req.max_length or 2048,
            return_dense=True,
            return_sparse=False,
            return_colbert_vecs=False,
            normalize_embeddings=True,
        )
        return EmbedResponse(embedding=res["dense_vecs"][0].tolist(), model=_model_name)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/embed/batch", response_model=EmbedBatchResponse)
def embed_batch(req: EmbedBatchRequest):
    if not _model:
        raise HTTPException(status_code=503, detail="model loading")
    try:
        res = _model.encode(
            req.texts,
            batch_size=req.batch_size,
            max_length=req.max_length,
            return_dense=True,
            return_sparse=False,
            return_colbert_vecs=False,
            normalize_embeddings=True,
        )
        return EmbedBatchResponse(
            embeddings=[v.tolist() for v in res["dense_vecs"]],
            model=_model_name
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
