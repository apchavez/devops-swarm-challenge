from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health() -> None:
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_hello() -> None:
    response = client.get("/hello")
    assert response.status_code == 200
    assert response.json() == {"message": "Hola mundo"}


def test_metrics() -> None:
    response = client.get("/metrics")
    assert response.status_code == 200
    assert b"http_requests_total" in response.content
