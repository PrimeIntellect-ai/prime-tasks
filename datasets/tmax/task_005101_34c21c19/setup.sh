#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip redis-server curl
pip3 install pytest flask redis numpy scipy pyyaml

mkdir -p /app/dna_pipeline
mkdir -p /app/corpus/clean
mkdir -p /app/corpus/evil

cat << 'EOF' > /app/dna_pipeline/config.yaml
redis_host: "127.0.0.1"
redis_port: 9999
api_port: 8080
EOF

cat << 'EOF' > /app/dna_pipeline/start.sh
#!/bin/bash
redis-server --port 6379 --daemonize yes
python3 /app/dna_pipeline/api.py &
python3 /app/dna_pipeline/worker.py &
EOF
chmod +x /app/dna_pipeline/start.sh

cat << 'EOF' > /app/dna_pipeline/api.py
import yaml
import redis
import json
import uuid
import time
from flask import Flask, request, jsonify

app = Flask(__name__)

with open("/app/dna_pipeline/config.yaml", "r") as f:
    config = yaml.safe_load(f)

r = redis.Redis(host=config.get("redis_host", "127.0.0.1"), port=config.get("redis_port", 6379))

@app.route('/classify', methods=['POST'])
def classify():
    data = request.get_json()
    seq = data.get("sequence", "")
    task_id = str(uuid.uuid4())
    r.lpush("task_queue", json.dumps({"task_id": task_id, "sequence": seq}))

    # Wait for result
    while True:
        res = r.get(f"result:{task_id}")
        if res:
            return jsonify({"status": res.decode('utf-8')})
        time.sleep(0.1)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=config.get("api_port", 5000))
EOF

cat << 'EOF' > /app/dna_pipeline/worker.py
import yaml
import redis
import json
import time
from classifier import evaluate_sequence

with open("/app/dna_pipeline/config.yaml", "r") as f:
    config = yaml.safe_load(f)

r = redis.Redis(host=config.get("redis_host", "127.0.0.1"), port=config.get("redis_port", 6379))

def main():
    while True:
        task = r.rpop("task_queue")
        if task:
            task_data = json.loads(task)
            task_id = task_data["task_id"]
            seq = task_data["sequence"]
            result = evaluate_sequence(seq)
            r.set(f"result:{task_id}", result, ex=60)
        else:
            time.sleep(0.1)

if __name__ == '__main__':
    main()
EOF

cat << 'EOF' > /app/dna_pipeline/classifier.py
def evaluate_sequence(dna_string):
    return "clean"
EOF

python3 -c '
import random
import os

random.seed(42)
clean_dir = "/app/corpus/clean"
evil_dir = "/app/corpus/evil"

bases = ["A", "C", "G", "T"]

def generate_clean():
    return "GCATCGAT" + "".join(random.choices(bases, k=200))

def generate_evil_no_prefix():
    return "".join(random.choices(bases, k=208))

def generate_evil_periodic():
    pattern = "".join(random.choices(bases, k=5))
    seq = "GCATCGAT" + (pattern * 40)
    # Add minor noise
    seq_list = list(seq)
    for _ in range(5):
        idx = random.randint(8, 207)
        seq_list[idx] = random.choice(bases)
    return "".join(seq_list)

for i in range(10):
    with open(os.path.join(clean_dir, f"clean_{i}.txt"), "w") as f:
        f.write(generate_clean())

for i in range(5):
    with open(os.path.join(evil_dir, f"evil_noprefix_{i}.txt"), "w") as f:
        f.write(generate_evil_no_prefix())

for i in range(5):
    with open(os.path.join(evil_dir, f"evil_periodic_{i}.txt"), "w") as f:
        f.write(generate_evil_periodic())
'

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
