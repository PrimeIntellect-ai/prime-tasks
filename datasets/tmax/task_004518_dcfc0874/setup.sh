#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server curl
    pip3 install pytest fastapi uvicorn redis requests python-dotenv pydantic

    mkdir -p /app

    cat << 'EOF' > /app/.env
REDIS_MAX_CONNECTIONS=5
EOF

    cat << 'EOF' > /app/api.py
import os
import json
from fastapi import FastAPI
from pydantic import BaseModel
import redis
from dotenv import load_dotenv

load_dotenv('/app/.env')

app = FastAPI()
r = redis.Redis(host='localhost', port=6379, db=0)

class Task(BaseModel):
    id: int
    payload: str

@app.post("/enqueue")
def enqueue(task: Task):
    r.lpush("task_queue", json.dumps({"id": task.id, "payload": task.payload}))
    return {"status": "queued"}
EOF

    cat << 'EOF' > /app/worker.py
import time
import os
import redis
import concurrent.futures
from dotenv import load_dotenv

load_dotenv('/app/.env')

max_connections = int(os.getenv('REDIS_MAX_CONNECTIONS', 5))
pool = redis.ConnectionPool(host='localhost', port=6379, db=0, max_connections=max_connections)
r = redis.Redis(connection_pool=pool)

def process_task(task):
    try:
        time.sleep(0.05)
        r.incr('processed_count')
    except Exception as e:
        # Fails silently due to connection pool exhaustion
        pass

def worker_loop():
    with concurrent.futures.ThreadPoolExecutor(max_workers=50) as executor:
        while True:
            try:
                task = r.brpop("task_queue", timeout=1)
                if task:
                    executor.submit(process_task, task)
            except Exception as e:
                time.sleep(0.1)

if __name__ == "__main__":
    worker_loop()
EOF

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
sleep 1
uvicorn api:app --app-dir /app --host 127.0.0.1 --port 8000 > /dev/null 2>&1 &
python3 /app/worker.py > /dev/null 2>&1 &
EOF
    chmod +x /app/start_services.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
