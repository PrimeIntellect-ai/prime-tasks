#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/ticket_8492/logs
cd /home/user/ticket_8492

# Create the misconfigured .env file
echo "LOG_DIR=/var/log/legacy_app/logs" > .env

# Create the buggy Python script
cat << 'EOF' > aggregate_logs.py
import os
import json
import threading
from concurrent.futures import ThreadPoolExecutor

# Read config
env_file = ".env"
config = {}
with open(env_file, "r") as f:
    for line in f:
        if "=" in line:
            k, v = line.strip().split("=", 1)
            config[k] = v

log_dir = config.get("LOG_DIR", "./logs")

stats = {
    "total_requests": 0,
    "total_response_time": 0.0,
    "file_count": 0
}

def process_file(filepath):
    global stats
    local_reqs = 0
    local_time = 0.0

    with open(filepath, "r") as f:
        for line in f:
            parts = line.strip().split(",")
            if len(parts) == 2:
                local_reqs += 1
                local_time += float(parts[1])

    # Intentional race condition here
    current_reqs = stats["total_requests"]
    current_time = stats["total_response_time"]

    # Yielding thread slightly to ensure race condition triggers
    import time; time.sleep(0.001)

    stats["total_requests"] = current_reqs + local_reqs
    stats["total_response_time"] = current_time + local_time

    with threading.Lock(): # lock only for file count to make it tricky
        stats["file_count"] += 1

def main():
    if not os.path.exists(log_dir):
        print(f"Error: Log directory {log_dir} not found.")
        return

    files = [os.path.join(log_dir, f) for f in os.listdir(log_dir) if f.endswith(".txt")]

    with ThreadPoolExecutor(max_workers=10) as executor:
        executor.map(process_file, files)

    avg_time = stats["total_response_time"] / stats["total_requests"] if stats["total_requests"] > 0 else 0

    report = {
        "total_requests": stats["total_requests"],
        "average_response_time": round(avg_time, 2),
        "files_processed": stats["file_count"]
    }

    with open("report.json", "w") as f:
        json.dump(report, f, indent=4)
    print("Report generated.")

if __name__ == "__main__":
    main()
EOF

# Generate log files
python3 -c '
import os
import random

random.seed(42)
os.makedirs("logs", exist_ok=True)

for i in range(50):
    filename = f"logs/log_{i:03d}.txt"
    with open(filename, "w") as f:
        # Each file has 1000 lines
        for j in range(100):
            # Normal response times between 0.1 and 2.0
            time = random.uniform(0.1, 2.0)
            f.write(f"REQ_{i}_{j},{time:.3f}\n")

# Inject anomaly into log_027.txt
with open("logs/log_027.txt", "a") as f:
    f.write("REQ_027_ANOMALY,-99999.999\n")
'

chmod -R 777 /home/user
