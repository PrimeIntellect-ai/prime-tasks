#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user/logs

cat << 'EOF' > /home/user/log_aggregator.py
import threading
import os
import json
import time

event_counts = {"ERROR": 0, "WARN": 0, "INFO": 0}

def process_file(filepath):
    local_counts = {"ERROR": 0, "WARN": 0, "INFO": 0}
    with open(filepath, 'r') as f:
        for line in f:
            level = line.strip().split('|')[0]
            if level in local_counts:
                local_counts[level] += 1

    global event_counts
    for k, v in local_counts.items():
        temp = event_counts[k]
        # Forced context switch to exacerbate the race condition
        time.sleep(0.001)
        event_counts[k] = temp + v

def main():
    log_dir = "/home/user/logs"
    threads = []
    for filename in os.listdir(log_dir):
        if filename.endswith(".log"):
            t = threading.Thread(target=process_file, args=(os.path.join(log_dir, filename),))
            threads.append(t)
            t.start()

    for t in threads:
        t.join()

    with open("/home/user/summary.json", "w") as f:
        json.dump(event_counts, f)

if __name__ == "__main__":
    main()
EOF

chmod +x /home/user/log_aggregator.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
