#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo curl
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /app/generate_data.py
import json
import random
import math

random.seed(42)

raw_data = []
golden_data = []

sensors = ["A", "B"]
state = {s: {"last_val": 0.0, "window": []} for s in sensors}

for i in range(1000):
    sensor = random.choice(sensors)

    true_val = math.sin(i / 10.0) * 10 + 50

    is_missing = random.random() < 0.1
    is_outlier = random.random() < 0.05

    if is_missing:
        raw_val = None
    elif is_outlier:
        raw_val = true_val + random.choice([-100, 100])
    else:
        raw_val = true_val

    raw_record = {"timestamp": 1700000000 + i, "sensor_id": sensor, "value": raw_val}
    raw_data.append(raw_record)

    st = state[sensor]

    if raw_val is None:
        val = st["last_val"]
    else:
        val = raw_val

    window = st["window"]
    if len(window) >= 2:
        mean = sum(window) / len(window)
        stddev = math.sqrt(sum((x - mean)**2 for x in window) / len(window))
        if stddev > 0:
            z = (val - mean) / stddev
            if z > 3.0:
                val = mean + 3 * stddev
            elif z < -3.0:
                val = mean - 3 * stddev

    st["last_val"] = val
    st["window"].append(val)
    if len(st["window"]) > 20:
        st["window"].pop(0)

    golden_record = {"timestamp": 1700000000 + i, "sensor_id": sensor, "value": val}
    golden_data.append(golden_record)

with open("/app/raw_data.jsonl", "w") as f:
    for r in raw_data:
        f.write(json.dumps(r) + "\n")

with open("/app/golden.json", "w") as f:
    for r in golden_data:
        f.write(json.dumps(r) + "\n")
EOF

    python3 /app/generate_data.py

    cat << 'EOF' > /app/source.py
import time
import os

pipe_name = "/tmp/raw_data.pipe"
if not os.path.exists(pipe_name):
    os.mkfifo(pipe_name)

with open("/app/raw_data.jsonl", "r") as f_in:
    with open(pipe_name, "w") as f_out:
        for line in f_in:
            f_out.write(line)
            f_out.flush()
            time.sleep(0.001)
EOF

    cat << 'EOF' > /app/sink.py
import os

pipe_name = "/tmp/processed_data.pipe"
if not os.path.exists(pipe_name):
    os.mkfifo(pipe_name)

with open(pipe_name, "r") as f_in:
    with open("/tmp/final_output.json", "w") as f_out:
        for line in f_in:
            f_out.write(line)
            f_out.flush()
EOF

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
rm -f /tmp/raw_data.pipe /tmp/processed_data.pipe /tmp/final_output.json
mkfifo /tmp/raw_data.pipe
mkfifo /tmp/processed_data.pipe

python3 /app/sink.py &
SINK_PID=$!

python3 /app/source.py &
SOURCE_PID=$!

wait $SOURCE_PID
sleep 1
kill $SINK_PID || true
EOF
    chmod +x /app/start_services.sh

    cat << 'EOF' > /app/verify.py
import json
import math

try:
    with open("/tmp/final_output.json") as f:
        agent_data = [json.loads(line) for line in f]
    with open("/app/golden.json") as f:
        golden_data = [json.loads(line) for line in f]

    if len(agent_data) != len(golden_data):
        print(f"Length mismatch: {len(agent_data)} vs {len(golden_data)}")
        exit(1)

    mse = sum((a["value"] - g["value"])**2 for a, g in zip(agent_data, golden_data)) / len(golden_data)
    print(f"MSE: {mse}")
    if mse <= 0.001:
        print("PASS")
        exit(0)
    else:
        print("FAIL")
        exit(1)
except Exception as e:
    print(f"Error: {e}")
    exit(1)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
