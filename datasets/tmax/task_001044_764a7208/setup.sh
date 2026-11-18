#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server
    pip3 install pytest redis

    mkdir -p /app

    cat << 'EOF' > /app/ingest_service.py
import socket
import json
import redis
import threading

r = redis.Redis(host='localhost', port=6379, db=0)

def handle_client(client_socket):
    try:
        data = client_socket.recv(4096)
        if not data:
            return
        # Bug 1: Only decodes utf-8, crashes on Windows-1252
        text = data.decode('utf-8')
        r.lpush('sensor_queue', text)
    except Exception as e:
        pass
    finally:
        client_socket.close()

def start_server():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(('0.0.0.0', 8000))
    server.listen(1000)
    while True:
        client, addr = server.accept()
        threading.Thread(target=handle_client, args=(client,)).start()

if __name__ == '__main__':
    start_server()
EOF

    cat << 'EOF' > /app/worker_service.py
import redis
import json
import time
import multiprocessing

r = redis.Redis(host='localhost', port=6379, db=0)

def process_queue():
    if not r.exists('global_accumulator'):
        r.set('global_accumulator', '0.0')

    while True:
        item = r.brpop('sensor_queue', timeout=1)
        if item:
            _, data = item
            try:
                payload = json.loads(data)
                delta = payload.get('delta', 0.0)

                # Bug 2: Race condition
                # Bug 3: Float precision loss
                current = float(r.get('global_accumulator') or 0.0)
                new_val = current + delta
                r.set('global_accumulator', new_val)

                r.incr('processed_count')
            except Exception as e:
                pass

if __name__ == '__main__':
    processes = []
    for _ in range(8):
        p = multiprocessing.Process(target=process_queue)
        p.start()
        processes.append(p)
    for p in processes:
        p.join()
EOF

    cat << 'EOF' > /app/test_flow.py
import socket
import json
import threading
import time
import redis
from decimal import Decimal

NUM_REQUESTS = 15000

def send_payload(payload, encoding):
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.connect(('localhost', 8000))
        s.sendall(json.dumps(payload).encode(encoding))
        s.close()
    except Exception:
        pass

def run_test():
    r = redis.Redis(host='localhost', port=6379, db=0)
    r.flushall()
    r.set('global_accumulator', '0.0')
    r.set('processed_count', '0')

    threads = []
    delta = 2.8

    for i in range(NUM_REQUESTS):
        payload = {"id": i, "delta": delta}
        encoding = 'windows-1252' if i % 10 == 0 else 'utf-8'
        t = threading.Thread(target=send_payload, args=(payload, encoding))
        threads.append(t)
        t.start()
        if len(threads) >= 200:
            for t in threads:
                t.join()
            threads = []

    for t in threads:
        t.join()

    timeout = 30
    start = time.time()
    while time.time() - start < timeout:
        count = int(r.get('processed_count') or 0)
        if count >= NUM_REQUESTS:
            break
        time.sleep(0.5)

    final_val = r.get('global_accumulator')
    if final_val:
        with open('/home/user/final_result.txt', 'w') as f:
            f.write(final_val.decode('utf-8'))

if __name__ == '__main__':
    run_test()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
