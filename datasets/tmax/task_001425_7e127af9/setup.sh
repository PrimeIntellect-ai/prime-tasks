#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip strace
    pip3 install pytest

    mkdir -p /home/user/traces

    cat << 'EOF' > /tmp/setup_traces.py
import json
import os

os.makedirs("/home/user/traces", exist_ok=True)

for i in range(1000):
    filepath = f"/home/user/traces/trace_{i}.json"

    if i == 542:
        # Corrupted JSON
        with open(filepath, "w") as f:
            f.write('{"timestamp": 169000000, "cpu_util": 45.2, "mem": [1,2,3')
    elif i == 888:
        # Missing key
        with open(filepath, "w") as f:
            json.dump({"timestamp": 169000000, "mem_util": 88.1}, f)
    else:
        # Normal
        with open(filepath, "w") as f:
            json.dump({"timestamp": 169000000, "cpu_util": 10.0}, f)
EOF
    python3 /tmp/setup_traces.py
    rm /tmp/setup_traces.py

    cat << 'EOF' > /home/user/profiler.py
#!/usr/bin/env python3
import json
import os
import glob

def process_traces(trace_dir):
    total_cpu = 0.0
    files = glob.glob(os.path.join(trace_dir, "*.json"))

    # Intentionally storing open file objects to cause an FD leak (EMFILE)
    open_files = []

    for filepath in files:
        f = open(filepath, 'r')
        open_files.append(f)

        data = json.loads(f.read())
        total_cpu += data["cpu_util"]

    print(f"Total CPU processed: {total_cpu}")

if __name__ == "__main__":
    process_traces("/home/user/traces")
EOF

    chmod +x /home/user/profiler.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
