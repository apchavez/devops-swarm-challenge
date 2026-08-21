from fastapi import FastAPI

app = FastAPI(title="devops-swarm-challenge")


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.get("/hello")
def hello() -> dict:
    return {"message": "Hola mundo"}
