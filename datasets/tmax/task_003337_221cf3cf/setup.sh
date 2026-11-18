#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip redis-server gcc
pip3 install pytest flask redis pandas numpy

mkdir -p /app

cat << 'EOF' > /app/api.py
import flask
import redis
import json

app = flask.Flask(__name__)
r = redis.Redis(host='localhost', port=6380, db=0)

@app.route('/data/train')
def train():
    data = r.get('train')
    return data if data else "[]"

@app.route('/data/test')
def test():
    data = r.get('test')
    return data if data else "[]"

if __name__ == '__main__':
    app.run(port=5000)
EOF

cat << 'EOF' > /app/load_redis.py
import redis
import json

r = redis.Redis(host='localhost', port=6379, db=0)
train_data = [
    {"id": 1, "text": "hello world", "label": 1},
    {"id": 2, "text": "bad text", "label": 0},
    {"id": 3, "text": "missing label", "label": None},
    {"id": 4, "text": "a " * 60, "label": 1}
]
test_data = [
    {"id": 5, "text": "hello", "label": None},
    {"id": 6, "text": "bad", "label": None}
]
r.set('train', json.dumps(train_data))
r.set('test', json.dumps(test_data))
EOF

cat << 'EOF' > /app/ground_truth.csv
id,probability_class_1
5,0.75
6,0.25
EOF

cat << 'EOF' > /app/verify.py
import pandas as pd
import numpy as np
import sys

try:
    pred_df = pd.read_csv("/home/user/predictions.csv")
    truth_df = pd.read_csv("/app/ground_truth.csv")

    # Merge on id to ensure alignment
    merged = pd.merge(truth_df, pred_df, on="id", suffixes=('_true', '_pred'))

    mse = np.mean((merged['probability_class_1_true'] - merged['probability_class_1_pred'])**2)
    print(f"MSE: {mse}")

    if mse <= 0.0001:
        sys.exit(0)
    else:
        sys.exit(1)
except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user /app
