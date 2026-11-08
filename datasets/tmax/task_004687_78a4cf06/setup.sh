#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git redis-server gcc make
    pip3 install pytest flask gunicorn requests

    # Create directories
    mkdir -p /app/data
    mkdir -p /app/compute_engine
    mkdir -p /app/frontend

    # Create WAL file with exact size 3230
    printf "WAL_v1.0\0\0\0\0\0\0\0\0" > /app/data/engine.wal
    dd if=/dev/zero bs=32 count=100 >> /app/data/engine.wal
    dd if=/dev/zero bs=14 count=1 >> /app/data/engine.wal

    # Set up compute_engine git repo
    cd /app/compute_engine
    git init
    git config user.email "oncall@example.com"
    git config user.name "Oncall Engineer"

    cat << 'EOF' > Makefile
CC=gcc
CFLAGS=-O3 -Wall
LDFLAGS= # missing -lpthread

engine: main.c queue.c
	$(CC) $(CFLAGS) -o engine main.c queue.c $(LDFLAGS)
EOF

    cat << 'EOF' > queue.c
// Buggy queue implementation
int enqueue(queue_t *q, void *item) {
    if ((q->tail + 1) % q->capacity <= q->head) {
        return -1; // Queue full
    }
    // ...
    return 0;
}
EOF

    touch main.c
    git add Makefile queue.c main.c
    git commit -m "Initial commit"

    # Introduce bug
    git commit --allow-empty -m "Optimize ring buffer boundary"

    # Create frontend files
    cat << 'EOF' > /app/frontend/api.py
from flask import Flask
app = Flask(__name__)

@app.route('/process')
def process():
    return "OK"
EOF

    # Create scripts
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes --port 6379
cd /app/compute_engine && ./engine &
cd /app/frontend && gunicorn -b 127.0.0.1:8080 api:app &
EOF
    chmod +x /app/start_services.sh

    cat << 'EOF' > /app/load_test.py
import time
import requests

def main():
    start = time.time()
    # Mock load test
    print(f"RESULT_RUNTIME_SECONDS: {time.time() - start}")

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
