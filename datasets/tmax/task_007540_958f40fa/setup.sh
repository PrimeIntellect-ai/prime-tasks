#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv nginx
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/workspace/app /home/user/workspace/tests /home/user/workspace/logs
    cd /home/user/workspace

    cat << 'EOF' > app/requirements.txt
Flask==2.3.3
Werkzeug==2.3.7
pytest==7.4.2
requests==2.31.0
EOF

    python3 -m venv venv
    . venv/bin/activate
    pip install -r app/requirements.txt

    cat << 'EOF' > nginx.conf
worker_processes 1;
daemon off;
error_log /home/user/workspace/logs/error.log;
pid /home/user/workspace/logs/nginx.pid;
events {
    worker_connections 1024;
}
http {
    access_log /home/user/workspace/logs/access.log;
    client_body_temp_path /home/user/workspace/logs/client_body;
    proxy_temp_path /home/user/workspace/logs/proxy_temp;
    fastcgi_temp_path /home/user/workspace/logs/fastcgi_temp;
    uwsgi_temp_path /home/user/workspace/logs/uwsgi_temp;
    scgi_temp_path /home/user/workspace/logs/scgi_temp;

    server {
        listen 8080;
        server_name localhost;

        location /api/v1/graph/ {
            # BUG: Stripping query parameters by hardcoding URI without args
            proxy_pass http://127.0.0.1:5000/api/v1/graph;
        }
    }
}
EOF

    cat << 'EOF' > app/main.py
from flask import Flask, request, jsonify
# BUG: importing algorithms here, but algorithms imports app from main.
# It causes ALGORITHM_REGISTRY to be evaluated before functions are registered if not careful.
from algorithms import ALGORITHM_REGISTRY

app = Flask(__name__)

@app.route('/api/v1/graph/<algo>', methods=['POST'])
def compute(algo):
    if algo not in ALGORITHM_REGISTRY:
        return jsonify({"error": "Algorithm not found"}), 404

    data = request.json
    start_node = request.args.get('start_node')
    end_node = request.args.get('end_node')

    if not start_node or not end_node:
        return jsonify({"error": "Missing start_node or end_node query parameters"}), 400

    try:
        result = ALGORITHM_REGISTRY[algo](data['graph'], start_node, end_node)
        return jsonify({"result": result})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(port=5000)
EOF

    cat << 'EOF' > app/algorithms.py
ALGORITHM_REGISTRY = {}

def register(name):
    def decorator(func):
        ALGORITHM_REGISTRY[name] = func
        return func
    return decorator

# BUG: Circular import that breaks registry on startup
import main 

@register("shortest_path")
def shortest_path(graph, start, end):
    # Mock implementation for brevity
    return 0.0

@register("critical_path")
def critical_path(graph, start, end):
    """
    Finds the maximum sum of weights on any path from start to end in a DAG.
    graph is a dict: {node: {neighbor: weight}}
    """
    # TODO: Implement critical path in DAG
    pass
EOF

    cat << 'EOF' > tests/test_integration.py
import requests
import pytest

BASE_URL = "http://localhost:8080/api/v1/graph"

def test_critical_path():
    graph = {
        "A": {"B": 3.0, "C": 2.0},
        "B": {"D": 4.0},
        "C": {"D": 6.0},
        "D": {}
    }

    response = requests.post(
        f"{BASE_URL}/critical_path?start_node=A&end_node=D",
        json={"graph": graph}
    )

    assert response.status_code == 200, f"Failed: {response.text}"
    assert response.json() == {"result": 8.0}
EOF

    cat << 'EOF' > run_services.sh
#!/bin/bash
source /home/user/workspace/venv/bin/activate
nginx -c /home/user/workspace/nginx.conf -p /home/user/workspace/ &
export NGINX_PID=$!
cd app && python main.py &
export FLASK_PID=$!
sleep 2
EOF
    chmod +x run_services.sh

    chown -R user:user /home/user
    chmod -R 777 /home/user
