import hashlib
import os
from typing import List
from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel
import chromadb
from chromadb.api.types import Documents, EmbeddingFunction, Embeddings

class HashEmbeddingFunction(EmbeddingFunction[Documents]):
    def __init__(self, dim: int = 384):
        self.dim = dim

    @staticmethod
    def name() -> str:
        return "hash_embedding_384"

    def get_config(self) -> dict:
        return {"dim": self.dim}

    @staticmethod
    def build_from_config(config: dict):
        return HashEmbeddingFunction(dim=config.get("dim", 384))

    def __call__(self, input: Documents) -> Embeddings:
        embeddings: Embeddings = []
        for text in input:
            vec: List[float] = []
            for i in range(self.dim):
                h = hashlib.sha256(f"{i}:{text}".encode("utf-8")).digest()
                val = (int.from_bytes(h[:4], "big") / 4294967295.0) * 2.0 - 1.0
                vec.append(float(val))
            norm = sum(x * x for x in vec) ** 0.5 or 1.0
            embeddings.append([x / norm for x in vec])
        return embeddings

def get_chroma_client():
    mode = os.getenv("CHROMA_MODE", "persistent").lower()
    if mode == "ephemeral":
        return chromadb.EphemeralClient()
    path = os.getenv("CHROMA_PATH", "/data")
    return chromadb.PersistentClient(path=path)

app = FastAPI(title="RAG Retrieval API", version="1.0.0")

client = get_chroma_client()
embedding_fn = HashEmbeddingFunction(dim=384)
collection = client.get_or_create_collection(
    name="documents",
    embedding_function=embedding_fn
)

class IngestRequest(BaseModel):
    id: str
    text: str

@app.get("/health")
def health():
    if os.getenv("SIMULATE_FAILURE", "false").lower() in ("true", "1", "yes"):
        raise HTTPException(status_code=500, detail="Simulated failure triggered")
    try:
        hb = client.heartbeat()
        if hb is None:
            raise Exception("Heartbeat returned None")
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"ChromaDB unreachable: {exc}")
    return {"status": "ok"}

@app.post("/ingest")
def ingest(payload: IngestRequest):
    collection.upsert(
        ids=[payload.id],
        documents=[payload.text]
    )
    return {"status": "success", "id": payload.id}

@app.get("/search")
def search(q: str = Query(..., min_length=1), k: int = Query(default=3, ge=1)):
    count = collection.count()
    if count == 0:
        return {"query": q, "results": []}
    limit = min(k, count)
    results = collection.query(query_texts=[q], n_results=limit)
    docs = []
    ids = results.get("ids", [[]])[0]
    documents = results.get("documents", [[]])[0]
    for idx, doc_id in enumerate(ids):
        docs.append({
            "id": doc_id,
            "text": documents[idx] if idx < len(documents) else ""
        })
    return {"query": q, "results": docs}
