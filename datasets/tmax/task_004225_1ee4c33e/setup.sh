#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip docker.io docker-compose
    pip3 install pytest flask psycopg2-binary pymongo requests

    mkdir -p /app

    cat << 'EOF' > /app/docker-compose.yml
version: '3.8'
services:
  mongodb:
    image: mongo:latest
    ports:
      - "27017:27017"
    volumes:
      - ./mongo-init.js:/docker-entrypoint-initdb.d/mongo-init.js:ro

  postgres:
    image: postgres:13
    environment:
      POSTGRES_USER: etl_user
      POSTGRES_PASSWORD: etl_pass
      POSTGRES_DB: etl_db
    ports:
      - "5432:5432"
    volumes:
      - ./postgres-init.sql:/docker-entrypoint-initdb.d/init.sql:ro
EOF

    cat << 'EOF' > /app/mongo-init.js
db = db.getSiblingDB('activity');
db.events.insertMany([
  {"user_id": 1, "status": "completed", "duration": 120},
  {"user_id": 1, "status": "failed", "duration": 40},
  {"user_id": 2, "status": "completed", "duration": 300}
]);
EOF

    cat << 'EOF' > /app/postgres-init.sql
CREATE TABLE users (user_id INT PRIMARY KEY, username VARCHAR(50), department VARCHAR(50));
INSERT INTO users VALUES (1, 'alice', 'engineering'), (2, 'bob', 'engineering'), (3, 'charlie', 'sales');
EOF

    cat << 'EOF' > /app/etl_service.py
from flask import Flask, request, jsonify
import psycopg2
from pymongo import MongoClient

app = Flask(__name__)

# TODO: Implement the /api/v1/user-activity endpoint

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8080)
EOF

    chmod -R 777 /app
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
