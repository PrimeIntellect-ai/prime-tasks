#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip git
pip3 install pytest

mkdir -p /app/vendored/log_timeline_api/log_timeline_api
cd /app/vendored/log_timeline_api

cat << 'EOF' > log_timeline_api/__init__.py
EOF

cat << 'EOF' > log_timeline_api/server.py
from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import argparse
from log_timeline_api.analyzer import Analyzer

analyzer = Analyzer()

class RequestHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/ingest':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            logs = json.loads(post_data)
            analyzer.ingest(logs)
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'{"status": "ok"}')
        else:
            self.send_response(404)
            self.end_headers()

    def do_GET(self):
        if self.path == '/anomalies':
            anomalies = analyzer.get_anomalies()
            self.send_response(200)
            self.end_headers()
            self.wfile.write(json.dumps(anomalies).encode('utf-8'))
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=9000)
    args = parser.parse_args()
    server = HTTPServer(('127.0.0.1', args.port), RequestHandler)
    server.serve_forever()
EOF

cat << 'EOF' > log_timeline_api/analyzer.py
import math
from datetime import datetime

def parse_time(ts):
    return datetime.fromisoformat(ts.replace('Z', '+00:00'))

class Analyzer:
    def __init__(self):
        self.logs = []

    def ingest(self, logs):
        self.logs.extend(logs)

    def get_anomalies(self):
        if not self.logs:
            return []

        parsed_logs = []
        for log in self.logs:
            try:
                dt = parse_time(log['timestamp'])
                parsed_logs.append((dt, log))
            except Exception:
                pass

        parsed_logs.sort(key=lambda x: x[0])

        valid_logs = []
        last_dt = None
        for dt, log in parsed_logs:
            if last_dt is not None:
                delta = (dt - last_dt).total_seconds()
                if delta < 0:
                    continue
            last_dt = dt
            valid_logs.append(log)

        if not valid_logs:
            return []

        latencies = [log['latency_ms'] for log in valid_logs]
        if not latencies:
            return []

        mean = sum(latencies) / len(latencies)
        variance = sum((x - mean) ** 2 for x in latencies) / len(latencies)
        std_dev = math.sqrt(variance)

        anomalies = []
        for log in valid_logs:
            if log['latency_ms'] > mean + 2 * std_dev:
                anomalies.append(log)

        return anomalies
EOF

git config --global init.defaultBranch main
git config --global user.email "dev@example.com"
git config --global user.name "Dev"

git init
git add .
git commit -m "Initial commit"
git tag v1.0

for i in $(seq 1 141); do
    echo "dummy $i" > dummy.txt
    git add dummy.txt
    git commit -m "Dummy commit $i"
done

cat << 'EOF' > log_timeline_api/analyzer.py
import math
from datetime import datetime

def parse_time(ts):
    time_str = ts[11:19]
    return datetime.strptime(time_str, "%H:%M:%S")

class Analyzer:
    def __init__(self):
        self.logs = []

    def ingest(self, logs):
        self.logs.extend(logs)

    def get_anomalies(self):
        if not self.logs:
            return []

        parsed_logs = []
        for log in self.logs:
            try:
                dt = parse_time(log['timestamp'])
                parsed_logs.append((dt, log))
            except Exception:
                pass

        parsed_logs.sort(key=lambda x: x[0])

        valid_logs = []
        last_dt = None
        for dt, log in parsed_logs:
            if last_dt is not None:
                delta = (dt - last_dt).total_seconds()
                if delta < 0:
                    continue
            last_dt = dt
            valid_logs.append(log)

        if not valid_logs:
            return []

        latencies = [log['latency_ms'] for log in valid_logs]
        if not latencies:
            return []

        mean = sum(latencies) / len(latencies)
        variance = sum((x - mean) ** 2 for x in latencies) / len(latencies)
        std_dev = math.sqrt(variance)

        anomalies = []
        for log in valid_logs:
            if log['latency_ms'] > mean + 2 * std_dev:
                anomalies.append(log)

        return anomalies
EOF

git add log_timeline_api/analyzer.py
git commit -m "Refactor time parsing for performance"

for i in $(seq 143 200); do
    echo "dummy $i" > dummy.txt
    git add dummy.txt
    git commit -m "Dummy commit $i"
done

# Install the package in editable mode so the server command works
pip3 install -e . || true
# Create a simple setup.py to allow pip install -e .
cat << 'EOF' > setup.py
from setuptools import setup, find_packages
setup(
    name="log_timeline_api",
    version="1.0.0",
    packages=find_packages(),
)
EOF
pip3 install -e .

useradd -m -s /bin/bash user || true
chown -R user:user /app
chmod -R 777 /home/user
