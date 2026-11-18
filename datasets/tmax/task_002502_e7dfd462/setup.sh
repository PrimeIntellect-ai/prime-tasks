#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/math_service.py
from http.server import BaseHTTPRequestHandler, HTTPServer
from socketserver import ThreadingMixIn
import json
import math

state = {
    'count': 0,
    'sum': 0.0,
    'sum_sq': 0.0
}

class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
    pass

class RequestHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        global state
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length)

        try:
            data = json.loads(post_data).get('values', [])

            local_sum = 0
            local_sum_sq = 0
            local_count = 0

            for v in data:
                # Bug 1: Format parsing edge-case (fails on commas)
                val = float(v)
                local_sum += val
                local_sum_sq += val * val
                local_count += 1

            # Bug 3: Race condition (unlocked global state update)
            state['count'] += local_count
            state['sum'] += local_sum
            state['sum_sq'] += local_sum_sq

            # Bug 2: Numerical instability (naive variance calculation)
            mean = state['sum'] / state['count']
            variance = (state['sum_sq'] / state['count']) - (mean * mean)
            std_dev = math.sqrt(variance)

            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"std_dev": std_dev}).encode())

        except Exception as e:
            self.send_response(500)
            self.end_headers()
            self.wfile.write(str(e).encode())

if __name__ == '__main__':
    server = ThreadedHTTPServer(('127.0.0.1', 8080), RequestHandler)
    server.serve_forever()
EOF

    cat << 'EOF' > /home/user/traffic_gen.py
import urllib.request
import threading
import json
import time

def send_request(data):
    req = urllib.request.Request('http://127.0.0.1:8080', 
                                 data=json.dumps(data).encode(), 
                                 headers={'Content-Type': 'application/json'},
                                 method='POST')
    try:
        response = urllib.request.urlopen(req)
        print(f"Success: {response.read().decode()}")
    except Exception as e:
        print(f"Failed: {e}")

# Trigger format issue
send_request({"values": ["1,000.5", "2,000.5"]})

# Trigger numerical instability
send_request({"values": ["100000000.01", "100000000.02", "100000000.01"]})

# Trigger concurrency issue
threads = []
for i in range(50):
    t = threading.Thread(target=send_request, args=({"values": [1, 2, 3]},))
    threads.append(t)
    t.start()
for t in threads:
    t.join()
EOF

    chmod +x /home/user/math_service.py
    chmod +x /home/user/traffic_gen.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
