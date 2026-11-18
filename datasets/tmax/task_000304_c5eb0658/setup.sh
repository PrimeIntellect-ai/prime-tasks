#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server
    pip3 install pytest numpy flask redis

    # Create directories
    mkdir -p /app/config
    mkdir -p /opt/verifier

    # Create dummy data_api.py
    cat << 'EOF' > /app/data_api.py
from flask import Flask
import json

app = Flask(__name__)

@app.route('/')
def index():
    return "Data API"

if __name__ == '__main__':
    with open('/app/config/api.json') as f:
        config = json.load(f)
    app.run(port=config.get('port', 80))
EOF

    # Create dummy orchestrator.py
    cat << 'EOF' > /app/orchestrator.py
import json

if __name__ == '__main__':
    with open('/app/config/orchestrator.json') as f:
        config = json.load(f)
    print(f"Connecting to broker: {config.get('broker_url')}")
EOF

    # Create configs with wrong values
    cat << 'EOF' > /app/config/api.json
{
    "port": 80
}
EOF

    cat << 'EOF' > /app/config/orchestrator.json
{
    "broker_url": "amqp://127.0.0.1:5672"
}
EOF

    # Create oracle script
    cat << 'EOF' > /opt/verifier/oracle_processor.py
import sys
import json
import numpy as np

def run():
    input_data = json.load(sys.stdin)
    X = np.array(input_data['data'], dtype=float)
    X_mean = np.mean(X, axis=0)
    X_c = X - X_mean
    C = np.cov(X, rowvar=False, ddof=1)
    if C.ndim == 0:
        C = np.array([[C]])
    Y = np.dot(X_c, C)

    C_rounded = np.round(C, 4).tolist()
    Y_rounded = np.round(Y, 4).tolist()

    print(json.dumps({"covariance": C_rounded, "transformed": Y_rounded}))

if __name__ == '__main__':
    run()
EOF

    chmod +x /opt/verifier/oracle_processor.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
