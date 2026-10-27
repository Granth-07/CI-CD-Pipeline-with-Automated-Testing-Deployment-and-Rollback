import os
import pytest
from fastapi.testclient import TestClient

# Ensure ephemeral client is used in tests before importing app
os.environ["CHROMA_MODE"] = "ephemeral"
from app.main import app

@pytest.fixture
def client():
    # Ensure simulate failure is unset by default
    os.environ.pop("SIMULATE_FAILURE", None)
    with TestClient(app) as c:
        yield c

def test_health_ok(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}

def test_health_simulate_failure(client, monkeypatch):
    monkeypatch.setenv("SIMULATE_FAILURE", "true")
    response = client.get("/health")
    assert response.status_code == 500

def test_ingest_and_search(client):
    doc_id = "doc-101"
    doc_text = "CI/CD Pipeline with automated rollback and testing"
    ingest_resp = client.post("/ingest", json={"id": doc_id, "text": doc_text})
    assert ingest_resp.status_code == 200
    assert ingest_resp.json()["status"] == "success"

    search_resp = client.get("/search", params={"q": "automated rollback", "k": 3})
    assert search_resp.status_code == 200
    data = search_resp.json()
    assert "results" in data
    assert any(item["id"] == doc_id for item in data["results"])

def test_empty_query_returns_422(client):
    response = client.get("/search", params={"q": ""})
    assert response.status_code == 422
