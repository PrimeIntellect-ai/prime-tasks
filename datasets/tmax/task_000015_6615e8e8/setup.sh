#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 netcat-openbsd curl
    pip3 install pytest flask

    mkdir -p /app/data /app/query_api /app/ingestion_api /app/ground_truth /home/user

    # Create dummy database and CSV
    sqlite3 /app/data/routes.db "CREATE TABLE routes (source TEXT, destination TEXT, cost REAL); CREATE TABLE routes_cache (source TEXT, destination TEXT, cost REAL);"
    echo "source,destination,cost" > /app/data/new_routes.csv

    # Create Ground Truth
    cat << 'EOF' > /app/ground_truth/reference.json
[
  {"destination": "STORE_102", "total_cost": 45.5, "rank": 1},
  {"destination": "STORE_055", "total_cost": 48.0, "rank": 2}
]
EOF

    # Create Ingestion API
    cat << 'EOF' > /app/ingestion_api/app.py
from flask import Flask
app = Flask(__name__)
@app.route('/')
def index():
    return "Ingestion API"
if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    # Create Query API
    cat << 'EOF' > /app/query_api/app.py
from flask import Flask, request, jsonify
import sqlite3

app = Flask(__name__)

@app.route('/shortest_path')
def shortest_path():
    source = request.args.get('source')
    destination = request.args.get('destination')
    conn = sqlite3.connect('/app/data/routes.db')
    cur = conn.cursor()
    # Stale query
    cur.execute("SELECT * FROM routes_cache WHERE source=? AND destination=?", (source, destination))
    res = cur.fetchall()
    conn.close()
    return jsonify(res)

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5001)
EOF

    # Create a fake systemctl to allow the agent to restart the service
    cat << 'EOF' > /usr/local/bin/systemctl
#!/bin/bash
if [ "$1" == "--user" ] && [ "$2" == "restart" ] && [ "$3" == "query-api" ]; then
    pkill -f "python3 /app/query_api/app.py" || true
    nohup python3 /app/query_api/app.py >/dev/null 2>&1 &
    sleep 1
    exit 0
fi
echo "Fake systemctl: command not supported in this test environment"
exit 1
EOF
    chmod +x /usr/local/bin/systemctl

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
