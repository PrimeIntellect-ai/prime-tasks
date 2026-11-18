#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip docker.io docker-compose-v2 curl
    pip3 install pytest requests aiohttp

    mkdir -p /app/vendored_usermgmt/api
    mkdir -p /home/user

    cat << 'EOF' > /app/vendored_usermgmt/docker-compose.yml
version: '3.8'
services:
  api:
    build: ./api
    ports:
      - "8000:8000"
    environment:
      - DB_HOST=wrong_db_alias
      - DB_USER=postgres
      - DB_PASSWORD=postgres
      - DB_NAME=postgres
    networks:
      - frontend
    depends_on:
      - postgres_db

  postgres_db:
    image: postgres:13
    environment:
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=postgres
      - POSTGRES_DB=postgres
    networks:
      - backend

networks:
  frontend:
  backend:
EOF

    cat << 'EOF' > /app/vendored_usermgmt/api/Dockerfile
FROM python:3.9-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
EOF

    cat << 'EOF' > /app/vendored_usermgmt/api/requirements.txt
fastapi
uvicorn
asyncpg
pydantic
EOF

    cat << 'EOF' > /app/vendored_usermgmt/api/main.py
from fastapi import FastAPI, HTTPException
import asyncpg
import asyncio
import os
from pydantic import BaseModel

app = FastAPI()

DB_HOST = os.getenv("DB_HOST", "localhost")
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASSWORD = os.getenv("DB_PASSWORD", "postgres")
DB_NAME = os.getenv("DB_NAME", "postgres")

class User(BaseModel):
    username: str
    email: str
    role: str

@app.get("/health")
async def health():
    return {"status": "ok"}

@app.post("/users")
async def create_user(user: User):
    await asyncio.sleep(0.015)
    try:
        conn = await asyncpg.connect(user=DB_USER, password=DB_PASSWORD, database=DB_NAME, host=DB_HOST)
        await conn.execute("CREATE TABLE IF NOT EXISTS users (username text, email text, role text)")
        await conn.execute("INSERT INTO users (username, email, role) VALUES ($1, $2, $3)", user.username, user.email, user.role)
        await conn.close()
        return {"status": "created"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/users/count")
async def get_users_count():
    try:
        conn = await asyncpg.connect(user=DB_USER, password=DB_PASSWORD, database=DB_NAME, host=DB_HOST)
        await conn.execute("CREATE TABLE IF NOT EXISTS users (username text, email text, role text)")
        val = await conn.fetchval("SELECT COUNT(*) FROM users")
        await conn.close()
        return {"count": val}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/users")
async def delete_users():
    try:
        conn = await asyncpg.connect(user=DB_USER, password=DB_PASSWORD, database=DB_NAME, host=DB_HOST)
        await conn.execute("CREATE TABLE IF NOT EXISTS users (username text, email text, role text)")
        await conn.execute("DELETE FROM users")
        await conn.close()
        return {"status": "deleted"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
EOF

    python3 -c '
import random
with open("/home/user/legacy_users.txt", "w") as f:
    for i in range(10000):
        if i % 2 == 0:
            f.write(f"[USER-MIGRATE] username: user{i} | email: user{i}@example.com | role: user\n")
        else:
            f.write(f"DEBUG: Something happened at line {i}\n")
'

    useradd -m -s /bin/bash user || true
    chown -R user:user /app
    chmod -R 777 /home/user
