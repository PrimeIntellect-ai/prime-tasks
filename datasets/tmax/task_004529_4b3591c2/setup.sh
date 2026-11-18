#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server postgresql wget gcc curl
    pip3 install pytest fastapi uvicorn psycopg2-binary redis python-dotenv

    mkdir -p /app/backend
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil
    mkdir -p /home/user/cJSON

    # Download cJSON
    wget -q https://raw.githubusercontent.com/DaveGamble/cJSON/master/cJSON.h -O /home/user/cJSON/cJSON.h
    wget -q https://raw.githubusercontent.com/DaveGamble/cJSON/master/cJSON.c -O /home/user/cJSON/cJSON.c

    # Create corpus files
    cat << 'EOF' > /app/corpus/clean/1.json
{"backup_id": 1, "query": "SELECT * FROM users WHERE id = $1", "deps": [[1, 2], [2, 3], [1, 3]]}
EOF
    cat << 'EOF' > /app/corpus/clean/2.json
{"backup_id": 2, "query": "SELECT id FROM config", "deps": []}
EOF

    cat << 'EOF' > /app/corpus/evil/1_sqli.json
{"backup_id": 3, "query": "SELECT * FROM users WHERE name = 'admin'", "deps": [[1, 2]]}
EOF
    cat << 'EOF' > /app/corpus/evil/2_cycle.json
{"backup_id": 4, "query": "SELECT * FROM t WHERE id = $1", "deps": [[1, 2], [2, 3], [3, 1]]}
EOF
    cat << 'EOF' > /app/corpus/evil/3_schema.json
{"backup_id": 5, "query": "SELECT * FROM t", "deps": [[1, 2]], "extra": true}
EOF
    cat << 'EOF' > /app/corpus/evil/4_missing.json
{"backup_id": 6, "query": "SELECT * FROM t"}
EOF

    # Create nginx.conf (broken)
    cat << 'EOF' > /app/nginx.conf
events {}
http {
    server {
        listen 8080;
        # location /api/ { proxy_pass http://127.0.0.1:8000/; }
    }
}
EOF

    # Create backend .env (broken)
    cat << 'EOF' > /app/backend/.env
DB_HOST=localhost
DB_USER=wrong_user
DB_PASS=wrong_pass
DB_NAME=wrong_db
REDIS_HOST=localhost
REDIS_PORT=6379
EOF

    # Create backend app.py
    cat << 'EOF' > /app/backend/app.py
import os
from fastapi import FastAPI, Response
import psycopg2
import redis
from dotenv import load_dotenv

load_dotenv()

app = FastAPI()

@app.get("/health")
def health():
    try:
        conn = psycopg2.connect(
            host=os.getenv("DB_HOST"),
            user=os.getenv("DB_USER"),
            password=os.getenv("DB_PASS"),
            dbname=os.getenv("DB_NAME")
        )
        conn.close()
        r = redis.Redis(host=os.getenv("REDIS_HOST"), port=int(os.getenv("REDIS_PORT")))
        r.ping()
        return {"status": "healthy"}
    except Exception as e:
        return Response(status_code=500, content=str(e))
EOF

    # Create start_services.sh
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
service postgresql start
service redis-server start

sudo -u postgres psql -c "CREATE USER backup_user WITH PASSWORD 'secret';"
sudo -u postgres psql -c "CREATE DATABASE backups OWNER backup_user;"

nginx -c /app/nginx.conf &
cd /app/backend && uvicorn app:app --host 127.0.0.1 --port 8000 &
sleep 2
EOF
    chmod +x /app/start_services.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
