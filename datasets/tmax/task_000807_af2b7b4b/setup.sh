#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server curl
    pip3 install pytest flask redis rq networkx requests

    # Create directories
    mkdir -p /app/services/api
    mkdir -p /app/services/worker
    mkdir -p /home/user/corpus/clean
    mkdir -p /home/user/corpus/evil

    # Create broken configurations
    cat << 'EOF' > /app/services/api/config.py
REDIS_URL = "redis://invalid-host:6379/0"
EOF

    cat << 'EOF' > /app/services/worker/settings.py
BROKER_URL = "redis://invalid-host:6379/0"
EOF

    # Create Flask API
    cat << 'EOF' > /app/services/api/app.py
from flask import Flask, request, jsonify
from redis import Redis
from rq import Queue
import config
import uuid

app = Flask(__name__)
redis_conn = Redis.from_url(config.REDIS_URL)
q = Queue(connection=redis_conn)

def dummy_analytics(graph_data):
    return {"status": "success", "nodes": len(graph_data)}

@app.route('/process', methods=['POST'])
def process_graph():
    data = request.json
    job = q.enqueue(dummy_analytics, data)
    return jsonify({"job_id": job.id}), 202

@app.route('/status/<job_id>', methods=['GET'])
def get_status(job_id):
    job = q.fetch_job(job_id)
    if job is None:
        return jsonify({"status": "not_found"}), 404
    if job.is_finished:
        return jsonify({"status": "finished", "result": job.result}), 200
    if job.is_failed:
        return jsonify({"status": "failed"}), 500
    return jsonify({"status": "pending"}), 202

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

    # Create Worker script
    cat << 'EOF' > /app/services/worker/worker.py
from redis import Redis
from rq import Worker, Queue, Connection
import settings

redis_conn = Redis.from_url(settings.BROKER_URL)

if __name__ == '__main__':
    with Connection(redis_conn):
        worker = Worker(['default'])
        worker.work()
EOF

    # Create start_all.sh
    cat << 'EOF' > /app/services/start_all.sh
#!/bin/bash
service redis-server start
export PYTHONPATH=/app/services/api:/app/services/worker:$PYTHONPATH
nohup python3 /app/services/api/app.py > /tmp/api.log 2>&1 &
nohup python3 /app/services/worker/worker.py > /tmp/worker.log 2>&1 &
echo "Services started"
EOF
    chmod +x /app/services/start_all.sh

    # Create verify_services.py
    cat << 'EOF' > /app/verify_services.py
import requests
import time
import sys

def verify():
    try:
        res = requests.post("http://localhost:5000/process", json=[{"source": "A", "target": "B"}])
        res.raise_for_status()
        job_id = res.json()["job_id"]

        for _ in range(10):
            status_res = requests.get(f"http://localhost:5000/status/{job_id}")
            if status_res.status_code == 200 and status_res.json().get("status") == "finished":
                print("Services verified successfully.")
                sys.exit(0)
            time.sleep(1)

        print("Job did not finish in time.")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    verify()
EOF

    # Create corpus files
    cat << 'EOF' > /home/user/corpus/evil/evil1.json
[{"source": "A", "target": "B"}, {"source": "A", "target": "C"}, {"source": "A", "target": "D"}, {"source": "A", "target": "E"}, {"source": "A", "target": "F"}]
EOF

    cat << 'EOF' > /home/user/corpus/clean/clean1.json
[{"source": "A", "target": "B"}, {"source": "B", "target": "C"}, {"source": "A", "target": "C"}, {"source": "C", "target": "D"}]
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /app
    chmod -R 777 /home/user
