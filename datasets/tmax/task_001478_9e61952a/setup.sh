#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server nginx curl
    pip3 install pytest pandas scikit-learn flask redis pyarrow python-dotenv

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/services/api
    mkdir -p /home/user/services/nginx
    mkdir -p /home/user/storage

    # Create Flask App
    cat << 'EOF' > /home/user/services/api/app.py
import os
import json
import redis
from flask import Flask, jsonify
from dotenv import load_dotenv

load_dotenv()

app = Flask(__name__)
redis_url = os.getenv('REDIS_URL', 'redis://localhost:6379/0')
r = redis.Redis.from_url(redis_url)

@app.route('/api/features')
def features():
    try:
        r.ping()
    except Exception as e:
        return jsonify({"error": "Redis not connected"}), 500

    with open('/home/user/services/api/data.json', 'r') as f:
        data = json.load(f)
    return jsonify(data)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

    # Misconfigured .env
    echo "REDIS_URL=redis://localhost:9999/0" > /home/user/services/api/.env

    # Misconfigured nginx.conf
    cat << 'EOF' > /home/user/services/nginx/nginx.conf
events {}
http {
    server {
        listen 8080;
        location / {
            proxy_pass http://127.0.0.1:9999;
        }
        location /api/ {
            proxy_pass http://127.0.0.1:9999;
        }
    }
}
EOF

    # Start script
    cat << 'EOF' > /home/user/services/start_stack.sh
#!/bin/bash
redis-server --port 6380 --daemonize yes
cd /home/user/services/api
nohup python3 app.py > api.log 2>&1 &
cd /home/user/services/nginx
nohup nginx -c /home/user/services/nginx/nginx.conf -g "daemon off;" > nginx.log 2>&1 &
echo "Stack started."
EOF
    chmod +x /home/user/services/start_stack.sh

    # Generate Data
    cat << 'EOF' > /tmp/gen_data.py
import pandas as pd
import numpy as np
import json

np.random.seed(42)
n = 1000
user_id = np.arange(1, n+1)
churn = np.random.randint(0, 2, n)

session_duration = np.where(churn == 0, np.random.normal(100, 10, n), np.random.normal(50, 10, n))
click_rate = session_duration * 0.5 + np.random.normal(0, 2, n)

transaction_volume = np.where(churn == 0, np.random.normal(500, 50, n), np.random.normal(200, 50, n))
support_tickets = np.where(churn == 0, np.random.normal(1, 1, n), np.random.normal(5, 1, n))

outlier_idx = np.random.choice(n, 10, replace=False)
transaction_volume[outlier_idx] = 5000

missing_idx = np.random.choice(n, 50, replace=False)
support_tickets = support_tickets.astype(float)
support_tickets[missing_idx] = np.nan

rt_df = pd.DataFrame({
    'user_id': user_id.astype(int),
    'session_duration': session_duration,
    'click_rate': click_rate,
    'churn': churn.astype(int)
})

rt_data = rt_df.to_dict(orient='records')
with open('/home/user/services/api/data.json', 'w') as f:
    json.dump(rt_data, f)

hist_df = pd.DataFrame({
    'user_id': user_id.astype(int),
    'transaction_volume': transaction_volume,
    'support_tickets': support_tickets
})
hist_df.to_parquet('/home/user/storage/historical.parquet')
EOF
    python3 /tmp/gen_data.py

    chmod -R 777 /home/user
