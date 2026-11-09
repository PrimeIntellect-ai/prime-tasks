#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip make curl
    pip3 install pytest flask pandas scipy numpy

    # Create directories
    mkdir -p /home/user/data/raw
    mkdir -p /home/user/data/processed
    mkdir -p /app/statsserver

    # Generate raw data
    cat << 'EOF' > /tmp/gen_data.py
import pandas as pd
import numpy as np

np.random.seed(42)

# Generate sensor_1.csv
n1 = 100
df1 = pd.DataFrame({
    'timestamp': pd.date_range(start='2024-01-01', periods=n1, freq='H'),
    'sensor_id': ['S1'] * n1,
    'group': np.random.choice(['A', 'B'], size=n1),
    'value': np.random.normal(loc=10.0, scale=2.0, size=n1)
})
df1.loc[5, 'value'] = np.nan
df1.loc[10, 'value'] = 100.0 # Outlier
df1.to_csv('/home/user/data/raw/sensor_1.csv', index=False)

# Generate sensor_2.csv
n2 = 100
df2 = pd.DataFrame({
    'timestamp': pd.date_range(start='2024-01-05', periods=n2, freq='H'),
    'sensor_id': ['S2'] * n2,
    'group': np.random.choice(['A', 'B'], size=n2),
    'value': np.random.normal(loc=12.0, scale=2.5, size=n2)
})
df2.loc[15, 'value'] = np.nan
df2.loc[20, 'value'] = -50.0 # Outlier
df2.to_csv('/home/user/data/raw/sensor_2.csv', index=False)
EOF
    python3 /tmp/gen_data.py

    # Create statsserver app.py
    cat << 'EOF' > /app/statsserver/app.py
import os
import json
from flask import Flask, request, jsonify

app = Flask(__name__)

@app.route('/api/stats', methods=['GET'])
def get_stats():
    auth_header = request.headers.get('Authorization')
    if auth_header != 'Bearer token-stats-2024':
        return jsonify({"error": "Unauthorized"}), 401

    data_path = os.environ.get('STATS_DATA_PATH')
    if not data_path or not os.path.exists(data_path):
        return jsonify({"error": f"Data file not found at {data_path}"}), 404

    try:
        with open(data_path, 'r') as f:
            data = json.load(f)
        return jsonify(data)
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run()
EOF

    # Create statsserver Makefile with deliberate bugs
    cat << 'EOF' > /app/statsserver/Makefile
.PHONY: serve

serve:
	export STATS_DAT_PATH=/tmp/missing.json && \
	FLASK_APP=app.py python3 -m flask run --host=127.0.0.1 --port=8081
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chown -R user:user /app/statsserver
    chmod -R 777 /home/user
    chmod -R 777 /app/statsserver
