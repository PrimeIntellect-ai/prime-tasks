#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 binutils
    pip3 install pytest fastapi uvicorn requests

    mkdir -p /app/services /app/data /app/dumps /app/tests

    # Create dummy services
    cat << 'EOF' > /app/services/api_gateway.py
from fastapi import FastAPI
app = FastAPI()
@app.post("/book")
def book():
    return {"status": "queued"}
EOF

    cat << 'EOF' > /app/services/ticket_worker.py
import threading
import time

db_lock = threading.Lock()
api_lock = threading.Lock()

class ConnectionPool:
    def __init__(self):
        self.active = 0
        self.max_limit = 10
    def get_connection(self):
        self.active += 1
        if self.active > self.max_limit:
            raise Exception("ExhaustionError")
        return "conn"

def process_a():
    with db_lock:
        time.sleep(0.1)
        with api_lock:
            pass

def process_b():
    with api_lock:
        time.sleep(0.1)
        with db_lock:
            pass
EOF

    cat << 'EOF' > /app/services/payment_mock.py
from http.server import BaseHTTPRequestHandler, HTTPServer
class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        self.send_response(200)
        self.end_headers()
if __name__ == '__main__':
    HTTPServer(('', 8080), Handler).serve_forever()
EOF

    # Create DB and WAL
    sqlite3 /app/data/bookings.db "PRAGMA journal_mode=WAL; CREATE TABLE bookings (id INTEGER PRIMARY KEY, status TEXT);"
    # SQLite might clean up WAL on exit, so we force it to exist
    touch /app/data/bookings.db-wal

    # Create memory dump with the key
    echo "Some binary data PAYMENT_SEC_9a8b7c6d5e4f3g2h1 more binary data" > /app/dumps/worker_crash.core

    # Create start script
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
uvicorn services.api_gateway:app --port 8000 &
python3 services.payment_mock.py &
python3 services.ticket_worker.py &
wait
EOF
    chmod +x /app/start_services.sh

    # Create load test script
    cat << 'EOF' > /app/tests/load_test.py
import json
print(json.dumps({"successful": 5000, "throughput": 1250.4}))
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
