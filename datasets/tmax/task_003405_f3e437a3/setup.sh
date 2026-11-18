#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip netcat
    pip3 install pytest flask

    mkdir -p /app

    cat << 'EOF' > /app/generate_data.py
import random
import math
import json

random.seed(42)

start_ts = 1700000000
num_points = 100

raw_data = []
for i in range(num_points):
    ts = start_ts + i
    temp = 40.0 + 10.0 * math.sin(i / 10.0) + random.uniform(-2, 2)
    raw_data.append({"ts": ts, "temp": temp})

for i in random.sample(range(num_points), 5):
    raw_data[i]["temp"] = random.choice([200.0, -100.0])

keep_indices = sorted(random.sample(range(num_points), int(num_points * 0.8)))
raw_data = [raw_data[i] for i in keep_indices]

shuffled = []
for i in range(0, len(raw_data), 3):
    chunk = raw_data[i:i+3]
    random.shuffle(chunk)
    shuffled.extend(chunk)

with open('/app/raw_stream.csv', 'w') as f:
    for row in shuffled:
        f.write(f"{row['ts']},S1,{row['temp']:.2f}\n")

filtered = [r for r in raw_data if -50.0 <= r['temp'] <= 150.0]
filtered.sort(key=lambda x: x['ts'])

resampled = {}
last_valid = None
for ts in range(start_ts, start_ts + num_points):
    reading = next((r for r in filtered if r['ts'] == ts), None)
    if reading is not None:
        last_valid = reading['temp']
    if last_valid is not None:
        resampled[ts] = last_valid

truth = {}
for w_start in range(start_ts, start_ts + num_points, 10):
    w_end = w_start + 9
    window_vals = [resampled[ts] for ts in range(w_start, w_end + 1) if ts in resampled]
    if len(window_vals) == 10:
        truth[w_start] = sum(window_vals) / len(window_vals)

with open('/app/ground_truth.json', 'w') as f:
    json.dump(truth, f)
EOF

    python3 /app/generate_data.py

    cat << 'EOF' > /app/producer.py
import socket
import time
import sys

HOST = '127.0.0.1'
PORT = 9000

with open('/app/raw_stream.csv', 'r') as f:
    lines = f.readlines()

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind((HOST, PORT))
    s.listen()
    while True:
        conn, addr = s.accept()
        with conn:
            for line in lines:
                try:
                    conn.sendall(line.encode())
                    time.sleep(1)
                except:
                    break
EOF

    cat << 'EOF' > /app/aggregator_api.py
from flask import Flask, request
import json

app = Flask(__name__)

@app.route('/submit', methods=['POST'])
def submit():
    try:
        data = request.get_json(force=True)
        with open('/tmp/results.json', 'a') as f:
            f.write(json.dumps(data) + '\n')
        return "OK", 200
    except Exception as e:
        return str(e), 400

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8080)
EOF

    cat << 'EOF' > /app/startup.sh
#!/bin/bash
nohup python3 /app/producer.py > /dev/null 2>&1 &
nohup python3 /app/aggregator_api.py > /dev/null 2>&1 &
echo "Services started."
EOF
    chmod +x /app/startup.sh

    cat << 'EOF' > /app/verify.py
import json
import sys

try:
    with open('/app/ground_truth.json', 'r') as f:
        truth = {int(k): float(v) for k, v in json.load(f).items()}
except FileNotFoundError:
    print("Verifier error: missing ground_truth.json")
    sys.exit(1)

try:
    with open('/tmp/results.json', 'r') as f:
        results = [json.loads(line) for line in f if line.strip()]
except FileNotFoundError:
    print("Agent failed: /tmp/results.json not found")
    sys.exit(1)

if len(results) < 5:
    print(f"Agent failed: Not enough windows submitted ({len(results)} < 5)")
    sys.exit(1)

mse = 0.0
matched = 0
for r in results:
    w_start = r.get("window_start")
    a_temp = r.get("avg_temp")
    if w_start in truth:
        diff = truth[w_start] - a_temp
        mse += diff * diff
        matched += 1

if matched == 0:
    print("Agent failed: No matching window_starts found.")
    sys.exit(1)

mse = mse / matched

print(f"Matched windows: {matched}, MSE: {mse:.4f}")
if mse <= 0.5:
    print("SUCCESS")
    sys.exit(0)
else:
    print("FAILED")
    sys.exit(1)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
