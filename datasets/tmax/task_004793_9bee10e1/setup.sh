#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server curl
    pip3 install pytest pandas scikit-learn mlflow redis flask joblib

    mkdir -p /app

    cat << 'EOF' > /app/api.py
import os
from flask import Flask, Response
import redis

app = Flask(__name__)
# AGENT MUST FIX THIS LINE:
redis_client = redis.Redis(host='redis_db', port=6379)

@app.route('/data.csv')
def get_data():
    try:
        data = redis_client.get('dataset')
        if not data:
            with open('/app/raw.csv', 'r') as f:
                data = f.read()
            redis_client.set('dataset', data)
        return Response(data, mimetype='text/csv')
    except Exception as e:
        return Response("Error connecting to cache: " + str(e), status=500)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8000)
EOF

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
mlflow server --host 127.0.0.1 --port 5000 &
python3 /app/api.py &
sleep 3
EOF
    chmod +x /app/start_services.sh

    cat << 'EOF' > /app/generate_data.py
import pandas as pd
import numpy as np
import random
import string

np.random.seed(42)
random.seed(42)

def generate_query(num_tokens, num_unique):
    if num_unique > num_tokens:
        num_unique = num_tokens

    vocab = [''.join(random.choices(string.ascii_lowercase, k=random.randint(3, 8))) for _ in range(num_unique)]
    tokens = vocab.copy()
    while len(tokens) < num_tokens:
        tokens.append(random.choice(vocab))
    random.shuffle(tokens)
    return " ".join(tokens)

def generate_dataset(n):
    ids = []
    queries = []
    res_times = []
    for i in range(n):
        num_tokens = random.randint(5, 20)
        num_unique = random.randint(3, num_tokens)
        query = generate_query(num_tokens, num_unique)

        noise = np.random.normal(0, 2.0)
        res_time = 5.0 + 2.5 * num_tokens - 1.2 * num_unique + noise

        ids.append(i)
        queries.append(query)
        res_times.append(res_time)

    return pd.DataFrame({'id': ids, 'customer_query': queries, 'resolution_time': res_times})

train_df = generate_dataset(500)
test_df = generate_dataset(100)

train_df.to_csv('/app/raw.csv', index=False)
test_df.to_csv('/app/test_secret.csv', index=False)
EOF

    python3 /app/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
