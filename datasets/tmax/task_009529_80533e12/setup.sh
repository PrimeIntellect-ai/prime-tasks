#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/pipeline
    cd /home/user/pipeline

    # 1. Setup Python requirements with a conflict
    cat << 'EOF' > requirements.txt
Flask==2.0.1
Werkzeug==3.0.0
EOF

    # 2. Setup Git and the Secret
    git init
    git config user.name "Dev"
    git config user.email "dev@example.com"

    cat << 'EOF' > config.py
API_URL = "https://mock.api/data"
EOF
    git add config.py
    git commit -m "Initial commit"

    cat << 'EOF' > config.py
API_URL = "https://mock.api/data"
MOCK_API_KEY = "p3rf_s3cr3t_99xA"
EOF
    git add config.py
    git commit -m "Add API config"

    cat << 'EOF' > config.py
API_URL = "https://mock.api/data"
# MOCK_API_KEY removed for security
EOF
    git add config.py
    git commit -m "Remove secret"

    # 3. Setup buggy processor.py (Race Condition)
    cat << 'EOF' > processor.py
import threading
import time

class Processor:
    def __init__(self):
        self.processed_count = 0

    def process_record(self):
        # Intentional race condition
        current = self.processed_count
        time.sleep(0.0001) # Force context switch
        self.processed_count = current + 1

    def run(self, num_records=10000):
        threads = []
        for _ in range(num_records):
            t = threading.Thread(target=self.process_record)
            threads.append(t)
            t.start()

        for t in threads:
            t.join()

        return self.processed_count
EOF

    # 4. Setup buggy aggregator.py (Precision Loss)
    cat << 'EOF' > aggregator.py
import math

def aggregate_weights():
    # A sequence that causes catastrophic cancellation if standard sum() is used
    # 10^16 + 1.2345 - 10^16 + 2.3456 = 3.5801
    # Standard sum() yields 0.0 or inaccurate float
    weights = [1e16, 1.2345, -1e16, 2.3456]

    # Bug: standard sum
    total = sum(weights)
    return total
EOF

    # 5. Setup main.py
    cat << 'EOF' > main.py
import os
import json
import sys
from processor import Processor
from aggregator import aggregate_weights

if __name__ == "__main__":
    if os.environ.get("MOCK_API_KEY") != "p3rf_s3cr3t_99xA":
        print("Error: Invalid or missing MOCK_API_KEY environment variable.")
        sys.exit(1)

    print("Running processor...")
    p = Processor()
    count = p.run(10000)

    print("Running aggregator...")
    weight = aggregate_weights()

    result = {
        "records_processed": count,
        "total_weight": weight
    }

    with open("final_output.json", "w") as f:
        json.dump(result, f, indent=4)

    print("Pipeline finished successfully.")
EOF

    chown -R user:user /home/user/pipeline
    chmod -R 777 /home/user
