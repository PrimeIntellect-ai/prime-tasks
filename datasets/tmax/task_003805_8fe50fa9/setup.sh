#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/project/data
    mkdir -p /home/user/project/logs

    cat << 'EOF' > /home/user/project/supervisor.py
import configparser
import time
import subprocess
import sys

def run_services():
    config = configparser.ConfigParser()
    config.read('/home/user/project/services.ini')

    services = config.sections()
    started = set()
    processes = {}

    # Very naive dependency resolution for this exercise
    while len(started) < len(services):
        for svc in services:
            if svc in started:
                continue

            deps = config.get(svc, 'After', fallback=None)
            if deps and deps not in started:
                continue # Wait for dep

            cmd = config.get(svc, 'ExecStart')
            print(f"Starting {svc}...")
            processes[svc] = subprocess.Popen(cmd, shell=True)
            started.add(svc)
            time.sleep(1) # Simulate time taken for service to report "ready"

    failed = False
    for svc, p in processes.items():
        p.wait()
        if p.returncode != 0:
            print(f"Service {svc} failed with code {p.returncode}")
            failed = True

    if failed:
        sys.exit(1)
    else:
        print("All services completed successfully.")
        sys.exit(0)

if __name__ == "__main__":
    run_services()
EOF

    cat << 'EOF' > /home/user/project/services.ini
[data-fetcher]
ExecStart=python3 /home/user/project/data-fetcher.py

[analytics-worker]
ExecStart=python3 /home/user/project/analytics-worker.py
EOF

    cat << 'EOF' > /home/user/project/data-fetcher.py
import time
import os

print("Fetching data...")
time.sleep(2) # Simulate slow I/O
os.makedirs("/home/user/project/data", exist_ok=True)
with open("/home/user/project/data/metrics.csv", "w") as f:
    f.write("id,value\n1,100\n2,200\n")
print("Data fetched.")
EOF

    cat << 'EOF' > /home/user/project/analytics-worker.py
import sys
import time
import os

filepath = "/home/user/project/data/metrics.csv"

# Agent needs to wrap this in a retry loop
with open(filepath, "r") as f:
    data = f.read()
    print("Processed: " + str(len(data.splitlines())) + " lines.")
sys.exit(0)
EOF

    chmod +x /home/user/project/*.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
