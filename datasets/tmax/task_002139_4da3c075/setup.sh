#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server nginx zip curl
    pip3 install pytest pandas numpy scikit-learn flask requests redis

    mkdir -p /home/user/portal/static/datasets
    mkdir -p /home/user/corpora/evil/dataset_1
    mkdir -p /home/user/corpora/evil/dataset_2
    mkdir -p /home/user/corpora/clean/dataset_1
    mkdir -p /home/user/corpora/clean/dataset_2

    cat << 'EOF' > /home/user/portal/app.py
import os, subprocess, zipfile, tempfile, requests, redis
from flask import Flask, request, jsonify

app = Flask(__name__)
REDIS_PORT = 6380 # AGENT MUST FIX THIS TO 6379
NGINX_URL = "http://127.0.0.1:80/data/" # AGENT MUST FIX THIS TO http://127.0.0.1:8080/datasets/

@app.route('/analyze', methods=['POST'])
def analyze():
    data = request.json
    dataset_id = data.get("dataset_id")
    r = redis.Redis(host='localhost', port=REDIS_PORT, db=0)

    zip_url = f"{NGINX_URL}{dataset_id}.zip"
    resp = requests.get(zip_url)
    if resp.status_code != 200:
        return jsonify({"error": "dataset not found on nginx"}), 404

    with tempfile.TemporaryDirectory() as tmpdir:
        zip_path = os.path.join(tmpdir, "data.zip")
        with open(zip_path, 'wb') as f:
            f.write(resp.content)

        with zipfile.ZipFile(zip_path, 'r') as zip_ref:
            zip_ref.extractall(tmpdir)

        result = subprocess.run(
            ["python3", "/home/user/sanitizer.py", tmpdir],
            capture_output=True, text=True
        )

        output = result.stdout.strip()
        r.set(f"status:{dataset_id}", output)
        return jsonify({"status": output, "returncode": result.returncode})

if __name__ == '__main__':
    app.run(port=5000)
EOF

    cat << 'EOF' > /home/user/portal/start_services.sh
#!/bin/bash
# Start Redis
redis-server --port 6379 --daemonize yes
# Start Nginx
cat << 'INNER_EOF' > /tmp/nginx.conf
events {}
http {
    server {
        listen 8080;
        location /datasets/ {
            alias /home/user/portal/static/datasets/;
        }
    }
}
INNER_EOF
nginx -c /tmp/nginx.conf
# Start Flask
nohup python3 /home/user/portal/app.py > /home/user/portal/flask.log 2>&1 &
echo "Services started."
EOF
    chmod +x /home/user/portal/start_services.sh

    cat << 'EOF' > /tmp/generate_data.py
import pandas as pd
import numpy as np
import os

# Clean 1: Normal random data
df_train1 = pd.DataFrame({'id': range(100), 'f1': np.random.randn(100), 'f2': np.random.randn(100), 'target': np.random.randn(100)})
df_test1 = pd.DataFrame({'id': range(100, 150), 'f1': np.random.randn(50), 'f2': np.random.randn(50)})
df_train1.to_csv('/home/user/corpora/clean/dataset_1/train.csv', index=False)
df_test1.to_csv('/home/user/corpora/clean/dataset_1/test.csv', index=False)

# Clean 2: High correlation but < 0.99 (0.95)
x = np.random.randn(100)
y = x + np.random.randn(100) * 0.3
df_train2 = pd.DataFrame({'id': range(100), 'f1': x, 'target': y})
df_test2 = pd.DataFrame({'id': range(100, 150), 'f1': np.random.randn(50)})
df_train2.to_csv('/home/user/corpora/clean/dataset_2/train.csv', index=False)
df_test2.to_csv('/home/user/corpora/clean/dataset_2/test.csv', index=False)

# Evil 1: Target Leakage (f2 is exactly target * 2)
df_train3 = pd.DataFrame({'id': range(100), 'f1': np.random.randn(100), 'f2': np.random.randn(100), 'target': np.random.randn(100)})
df_train3['f2'] = df_train3['target'] * 2.0
df_test3 = pd.DataFrame({'id': range(100, 150), 'f1': np.random.randn(50), 'f2': np.random.randn(50)})
df_train3.to_csv('/home/user/corpora/evil/dataset_1/train.csv', index=False)
df_test3.to_csv('/home/user/corpora/evil/dataset_1/test.csv', index=False)

# Evil 2: Train/Test Overlap (row index 5 is identical in features)
df_train4 = pd.DataFrame({'id': range(100), 'f1': np.random.randn(100), 'f2': np.random.randn(100), 'target': np.random.randn(100)})
df_test4 = pd.DataFrame({'id': range(100, 150), 'f1': np.random.randn(50), 'f2': np.random.randn(50)})
df_test4.loc[0, 'f1'] = df_train4.loc[5, 'f1']
df_test4.loc[0, 'f2'] = df_train4.loc[5, 'f2']
df_train4.to_csv('/home/user/corpora/evil/dataset_2/train.csv', index=False)
df_test4.to_csv('/home/user/corpora/evil/dataset_2/test.csv', index=False)

# Create a sample test zip for the curl command
os.system("cd /home/user/corpora/clean/dataset_1 && zip -r /home/user/portal/static/datasets/test_sample.zip .")
EOF

    python3 /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
