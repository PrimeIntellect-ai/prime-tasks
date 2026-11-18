#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip docker.io docker-compose-v2
    pip3 install pytest pandas scikit-learn psycopg2-binary redis sqlalchemy

    mkdir -p /app

    cat << 'EOF' > /app/docker-compose.yml
version: '3.8'
services:
  postgres:
    image: postgres:13
    environment:
      POSTGRES_USER: admin
      POSTGRES_PASSWORD: secret
      POSTGRES_DB: etl_db
    ports:
      - "5432:5432"
  redis:
    image: redis:6
    ports:
      - "6379:6379"
EOF

    cat << 'EOF' > /app/pipeline.py
import pandas as pd
import redis
from sqlalchemy import create_engine
from sklearn.ensemble import RandomForestClassifier

def main():
    # Buggy pipeline
    pass

if __name__ == "__main__":
    main()
EOF

    cat << 'EOF' > /app/test_documents.csv
id,text
1,hello world
2,testing
EOF

    cat << 'EOF' > /app/ground_truth.csv
id,label
1,0
2,1
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
