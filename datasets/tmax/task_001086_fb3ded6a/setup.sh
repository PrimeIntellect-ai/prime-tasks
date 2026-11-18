#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip redis-server acl
pip3 install pytest redis

mkdir -p /app/processor

cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes --port 6379
sleep 1
python3 /app/emitter.py
EOF
chmod +x /app/start_services.sh

cat << 'EOF' > /app/emitter.py
import redis
import json
import random
r = redis.Redis(host='127.0.0.1', port=6379)
pipe = r.pipeline()
for i in range(50000):
    pipe.set(f"sensor:{i}", json.dumps({"id": f"sensor:{i}", "value": random.uniform(10.0, 100.0)}))
pipe.execute()
EOF

cat << 'EOF' > /app/benchmark.py
import sys, time, subprocess, json, os
if len(sys.argv) != 2: sys.exit(1)
script = sys.argv[1]
start = time.time()
res = subprocess.run([sys.executable, script])
elapsed = time.time() - start
if res.returncode != 0:
    print(f"Script failed with code {res.returncode}")
    sys.exit(1)
with open("/home/user/output_data/processed.jsonl") as f:
    lines = f.readlines()
if len(lines) != 50000:
    print("Invalid line count")
    sys.exit(1)
print(f"Metric: elapsed={elapsed}")
if elapsed > 1.5:
    print("Threshold failed: took longer than 1.5s")
    sys.exit(1)
sys.exit(0)
EOF

cat << 'EOF' > /app/processor/naive_processor.py
import redis
import json
import time

r = redis.Redis(host='localhost', port=6379)
for i in range(50000):
    val = r.get(f"sensor:{i}")
    if val:
        data = json.loads(val)
        data['processed_value'] = data['value'] * 1.5
        # write to file ...
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
