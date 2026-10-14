import os
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Literal
from fastapi.staticfiles import StaticFiles

import psycopg
from dotenv import load_dotenv
from fastapi import FastAPI
from fastapi.responses import FileResponse
from psycopg.rows import dict_row
from pydantic import BaseModel

BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR / ".env")


def get_conn():
    return psycopg.connect(
        host=os.getenv("DB_HOST", "localhost"),
        port=os.getenv("DB_PORT", "5432"),
        dbname=os.getenv("POSTGRES_DB"),
        user=os.getenv("POSTGRES_USER"),
        password=os.getenv("POSTGRES_PASSWORD"),
        row_factory=dict_row,
    )


@asynccontextmanager
async def lifespan(app: FastAPI):
    # при старте создаём таблицу, если её ещё нет
    with get_conn() as conn:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS moods (
                id SERIAL PRIMARY KEY,
                value TEXT NOT NULL,
                created_at TIMESTAMPTZ NOT NULL DEFAULT now()
            )
            """
        )
    yield


app = FastAPI(lifespan=lifespan)
from fastapi import Request

@app.middleware("http")
async def add_backend_header(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Backend"] = os.getenv("BACKEND_ID", "1")
    return response
app.mount("/images", StaticFiles(directory=BASE_DIR / "frontend" / "images"), name="images")

class MoodIn(BaseModel):
    value: Literal["great", "ok", "bad"]


@app.post("/api/moods")
def add_mood(mood: MoodIn):
    with get_conn() as conn:
        row = conn.execute(
            "INSERT INTO moods (value) VALUES (%s) RETURNING id, value, created_at",
            (mood.value,),
        ).fetchone()
    return row


@app.get("/api/moods")
def list_moods():
    with get_conn() as conn:
        rows = conn.execute(
            "SELECT id, value, created_at FROM moods ORDER BY created_at DESC LIMIT 20"
        ).fetchall()
    return rows


@app.get("/")
def index():
    return FileResponse(BASE_DIR / "frontend" / "index.html")
