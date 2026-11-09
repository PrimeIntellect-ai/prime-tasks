#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gawk
pip3 install pytest

mkdir -p /app

cat << 'EOF' > /app/docker-compose.yml
version: '3'
services:
  db:
    image: postgres:13
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: secret
      POSTGRES_DB: postgres
  data-api:
    image: python:3.9-slim
    volumes:
      - ./app.py:/app.py
    command: >
      bash -c "pip install flask psycopg2-binary && python /app.py"
    env_file:
      - .env
    ports:
      - "8080:8080"
EOF

cat << 'EOF' > /app/.env
DATABASE_URL=postgresql://postgres:secret@localhost:5432/postgres
EOF

cat << 'EOF' > /app/app.py
from flask import Flask
import os
import psycopg2

app = Flask(__name__)

@app.route('/health')
def health():
    try:
        conn = psycopg2.connect(os.environ.get('DATABASE_URL'))
        conn.close()
        return "OK", 200
    except Exception as e:
        return str(e), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF

cat << 'EOF' > /app/oracle_stats
#!/usr/bin/env python3
import sys
import csv

def main():
    reader = csv.reader(sys.stdin)
    try:
        next(reader)
    except StopIteration:
        print("Covariance: N/A")
        return

    data = []
    for row in reader:
        if not row:
            continue
        try:
            id_val = int(row[0])
            if id_val % 3 == 0:
                data.append((float(row[1]), float(row[2])))
        except ValueError:
            pass

    n = len(data)
    if n < 2:
        print("Covariance: N/A")
        return

    mean_x = sum(d[0] for d in data) / n
    mean_y = sum(d[1] for d in data) / n

    cov = sum((d[0] - mean_x) * (d[1] - mean_y) for d in data) / (n - 1)

    print(f"Covariance: {cov:.3f}")

if __name__ == "__main__":
    main()
EOF

chmod +x /app/oracle_stats

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
