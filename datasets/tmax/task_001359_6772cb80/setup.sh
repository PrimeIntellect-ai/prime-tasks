#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server curl jq gawk
    pip3 install pytest flask redis requests

    mkdir -p /app

    # Create Sensor API
    cat << 'EOF' > /app/sensor_api.py
from flask import Flask, Response
import random

app = Flask(__name__)

@app.route('/api/v1/logs')
def logs():
    # Return some dummy JSON lines
    data = '{"timestamp": "2024-01-01T12:01:15Z", "msg": "温度正常", "value": 42}\n'
    return Response(data, mimetype='application/json')

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5001)
EOF

    # Create Data Warehouse
    cat << 'EOF' > /app/data_warehouse.py
from flask import Flask, jsonify, request

app = Flask(__name__)

@app.route('/api/v1/load', methods=['POST'])
def load():
    return jsonify({"status": "success"})

@app.route('/api/v1/stats')
def stats():
    # Dummy stat for verifier
    return jsonify({"accuracy": 0.983})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5002)
EOF

    # Create Verifier
    cat << 'EOF' > /app/verifier.py
import requests
import sys

def verify():
    try:
        resp = requests.get("http://localhost:5002/api/v1/stats")
        resp.raise_for_status()
        data = resp.json()
        accuracy = data.get("accuracy", 0.0)
        if accuracy >= 0.95:
            print(f"Success: Accuracy is {accuracy}")
            sys.exit(0)
        else:
            print(f"Failure: Accuracy is {accuracy}, expected >= 0.95")
            sys.exit(1)
    except Exception as e:
        print(f"Error during verification: {e}")
        sys.exit(1)

if __name__ == "__main__":
    verify()
EOF

    # Create startup script
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
nohup python3 /app/sensor_api.py > /tmp/sensor.log 2>&1 &
nohup python3 /app/data_warehouse.py > /tmp/dw.log 2>&1 &
sleep 3
EOF
    chmod +x /app/start_services.sh

    # Create user and buggy ETL script
    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/etl_pipeline.sh
#!/bin/bash
# Buggy ETL Pipeline

# 1. Extract data with retries (Causes duplicates)
curl --retry 3 -s http://localhost:5001/api/v1/logs >> temp_data.jsonl

# 2. Process data (Buggy length check)
while IFS= read -r line; do
    msg=$(echo "$line" | jq -r '.msg')

    # Flaw: Uses byte count instead of character count
    len=$(echo -n "$msg" | wc -c)

    if [ "$len" -le 15 ]; then
        echo "$line" >> processed_data.jsonl
    fi
done < temp_data.jsonl

# 3. Load data
curl -X POST -H "Content-Type: application/json" -d @processed_data.jsonl http://localhost:5002/api/v1/load
EOF

    chmod +x /home/user/etl_pipeline.sh
    chmod -R 777 /home/user
