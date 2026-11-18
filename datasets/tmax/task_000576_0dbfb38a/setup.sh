#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip postgresql-client redis-tools
    pip3 install pytest psycopg2-binary redis

    mkdir -p /app

    cat << 'EOF' > /app/docker-compose.yml
version: '3.8'
services:
  postgres:
    image: postgres:14
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: password
      POSTGRES_DB: research
    ports:
      - "5432:5432"
    volumes:
      - ./init.sql:/docker-entrypoint-initdb.d/init.sql
  redis:
    image: redis:6
    ports:
      - "6379:6379"
  traffic_generator:
    image: python:3.10
    volumes:
      - ./traffic_generator.py:/app/traffic_generator.py
    command: ["python", "/app/traffic_generator.py"]
    depends_on:
      - postgres
EOF

    cat << 'EOF' > /app/init.sql
CREATE TABLE authors (
    id SERIAL PRIMARY KEY,
    score NUMERIC NOT NULL DEFAULT 0.0
);

CREATE TABLE citations (
    citing_author_id INTEGER REFERENCES authors(id),
    cited_author_id INTEGER REFERENCES authors(id),
    PRIMARY KEY (citing_author_id, cited_author_id)
);

INSERT INTO authors (id, score)
SELECT generate_series(1, 10000), random() * 100;

INSERT INTO citations (citing_author_id, cited_author_id)
SELECT 
    floor(random() * 10000 + 1), 
    floor(random() * 10000 + 1)
FROM generate_series(1, 50000)
ON CONFLICT DO NOTHING;
EOF

    cat << 'EOF' > /app/extract_graph.py
import psycopg2
import redis
import time

def main():
    conn = psycopg2.connect(host="localhost", dbname="research", user="postgres", password="password")
    r = redis.Redis(host="localhost", port=6379)
    cur = conn.cursor()

    cur.execute("SELECT id, score FROM authors WHERE score > 50.0 FOR UPDATE")
    authors = cur.fetchall()

    for author_id, score in authors:
        cur.execute("SELECT cited_author_id FROM citations WHERE citing_author_id = %s", (author_id,))
        cited = cur.fetchall()

        r.set(f"author:{author_id}:score", round(score, 2))
        for c in cited:
            r.sadd(f"author:{author_id}:cites", c[0])

    conn.commit()
    cur.close()
    conn.close()

if __name__ == "__main__":
    main()
EOF

    cat << 'EOF' > /app/traffic_generator.py
import psycopg2
import time
import random

def main():
    while True:
        try:
            conn = psycopg2.connect(host="postgres", dbname="research", user="postgres", password="password")
            conn.autocommit = True
            cur = conn.cursor()
            while True:
                author_id = random.randint(1, 10000)
                cur.execute("UPDATE authors SET score = score + %s WHERE id = %s", (random.random() * 0.1, author_id))
                time.sleep(0.01)
        except Exception as e:
            time.sleep(1)

if __name__ == "__main__":
    main()
EOF

    chmod +x /app/extract_graph.py
    chmod +x /app/traffic_generator.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
