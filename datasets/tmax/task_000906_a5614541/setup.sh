#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server curl
    pip3 install pytest flask fastapi uvicorn pandas scikit-learn redis python-multipart requests

    mkdir -p /app

    cat << 'EOF' > /app/config.json
{
  "REDIS_HOST": "127.0.0.1",
  "REDIS_PORT": 6380,
  "REDIS_PASS": ""
}
EOF

    cat << 'EOF' > /app/start.sh
#!/bin/bash
# Start redis
redis-server --port 6379 --requirepass stat-sec-99 --daemonize yes
sleep 2

# Start APIs
export REDIS_URL="redis://localhost:6380/0"
python3 /app/worker.py &
uvicorn report:app --app-dir /app --host 127.0.0.1 --port 5002 &
wait
EOF
    chmod +x /app/start.sh

    cat << 'EOF' > /app/worker.py
import os
import json
import pandas as pd
from flask import Flask, request, jsonify
from sklearn.model_selection import KFold, cross_val_score
from sklearn.linear_model import Ridge
import redis

app = Flask(__name__)

with open('/app/config.json') as f:
    config = json.load(f)

r = redis.Redis(host=config['REDIS_HOST'], port=config['REDIS_PORT'], password=config['REDIS_PASS'])

@app.route('/process', methods=['POST'])
def process():
    file = request.files['file']
    df = pd.read_csv(file)

    # Needs to be fixed
    X = df.drop(columns=['target', 'category'])
    y = df['target']

    corr_matrix = X.corr(method='pearson').to_dict()

    kf = KFold(n_splits=5, shuffle=True)
    model = Ridge(alpha=1.0)
    cv_scores = cross_val_score(model, X, y, cv=kf, scoring='r2')
    mean_cv_score = cv_scores.mean()

    r.set('cv_score', mean_cv_score)
    r.set('correlation_matrix', json.dumps(corr_matrix))

    return jsonify({"status": "success"})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5001)
EOF

    cat << 'EOF' > /app/report.py
import json
import os
from fastapi import FastAPI
import redis

app = FastAPI()

with open('/app/config.json') as f:
    config = json.load(f)

r = redis.Redis(host=config['REDIS_HOST'], port=config['REDIS_PORT'], password=config['REDIS_PASS'], decode_responses=True)

@app.get('/report')
def report():
    cv_score = r.get('cv_score')
    corr_matrix = r.get('correlation_matrix')
    if cv_score is None or corr_matrix is None:
        return {"error": "No data"}
    return {
        "cv_score": float(cv_score),
        "correlation_matrix": json.loads(corr_matrix)
    }
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
