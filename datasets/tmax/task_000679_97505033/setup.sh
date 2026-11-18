#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip git redis-server curl
pip3 install pytest flask redis requests

useradd -m -s /bin/bash user || true

mkdir -p /app/services
cat << 'EOF' > /app/services/start_all.sh
#!/bin/bash
service redis-server start
mkdir -p /app/services/data_service
cat << 'INNER_EOF' > /app/services/data_service/server.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import json

class RequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps({"data": []}).encode('utf-8'))
    def do_POST(self):
        self.do_GET()

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 9000), RequestHandler)
    server.serve_forever()
INNER_EOF
python3 /app/services/data_service/server.py &
EOF
chmod +x /app/services/start_all.sh

mkdir -p /app/api_repo
cd /app/api_repo
git init
git config user.email "dev@example.com"
git config user.name "Dev"

cat << 'EOF' > requirements.txt
Flask
redis
requests
EOF
git add requirements.txt
git commit -m "Initial commit"

cat << 'EOF' > app.py
from flask import Flask, request, jsonify
app = Flask(__name__)
@app.route('/query', methods=['POST'])
def query():
    return jsonify({"status": "success", "results": []})
if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8000)
EOF
git add app.py
git commit -m "Basic app"

echo "# comment 3" >> app.py
git commit -am "comment 3"

echo "# comment 4" >> app.py
git commit -am "comment 4"

cat << 'EOF' > app.py
from flask import Flask, request, jsonify
import redis
import requests

app = Flask(__name__)
cache = redis.Redis(host='127.0.0.1', port=6379)

@app.route('/query', methods=['POST'])
def query():
    payload = request.json or {}
    try:
        resp = requests.post('http://127.0.0.1:9000/')
        data = resp.json().get("data", [])
    except Exception:
        data = []
    return jsonify({"status": "success", "results": data})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8000)
EOF
git commit -am "Add redis and requests"
git tag v1.0

echo "# comment 6" >> app.py
git commit -am "comment 6"

cat << 'EOF' > app.py
from flask import Flask, request, jsonify
import redis
import requests

app = Flask(__name__)
cache = redis.Redis(host='127.0.0.1', port=6379)

@app.route('/query', methods=['POST'])
def query():
    payload = request.json or {}
    if payload.get("filters", {}).get("metadata", {}).get("is_archived"):
        # Bug: attempting to concatenate a string with a boolean in logging
        print("Fetching archived records: " + payload["filters"]["metadata"]["is_archived"])

    try:
        resp = requests.post('http://127.0.0.1:9000/')
        data = resp.json().get("data", [])
    except Exception:
        data = []
    return jsonify({"status": "success", "results": data})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8000)
EOF
git commit -am "Feature: filter by archive status"

echo "# comment 8" >> app.py
git commit -am "comment 8"

echo "# comment 9" >> app.py
git commit -am "comment 9"

echo "# comment 10" >> app.py
git commit -am "comment 10"

cat << 'EOF' > /home/user/customer_payload.json
{"query_id": "12345", "user": "admin", "filters": {"date_range": "2023", "metadata": {"is_archived": true, "tags": ["prod", "db"]}}, "limit": 100}
EOF

chmod -R 777 /app
chmod -R 777 /home/user
