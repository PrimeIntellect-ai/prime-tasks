#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create directories
    mkdir -p /app/vendor/cap-plan-tools-1.0.0
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Create aggregator.py
    cat << 'EOF' > /app/vendor/cap-plan-tools-1.0.0/aggregator.py
#!/usr/bin/env python3
import os
import sys

BASE_DIR = "/var/lib/cap_plan_root"

def main():
    if "--verify" in sys.argv:
        try:
            os.makedirs(BASE_DIR, exist_ok=True)
            with open(os.path.join(BASE_DIR, "state.db"), "w") as f:
                f.write("INIT")
            print("Verification successful.")
            sys.exit(0)
        except Exception as e:
            print(f"Error: {e}")
            sys.exit(1)

if __name__ == "__main__":
    main()
EOF
    chmod +x /app/vendor/cap-plan-tools-1.0.0/aggregator.py

    # Create clean corpus
    cat << 'EOF' > /app/corpora/clean/input.jsonl
{"process_name": "nginx", "cpu_percent": 12.5, "memory_mb": 256}
{"process_name": "python3", "cpu_percent": 50.0, "memory_mb": 1024}
EOF

    # Create evil corpus
    cat << 'EOF' > /app/corpora/evil/input.jsonl
{"process_name": "nginx", "cpu_percent": -5, "memory_mb": 256}
{"process_name": "nginx", "cpu_percent": 105, "memory_mb": 256}
{"process_name": "nginx", "cpu_percent": 12.5, "memory_mb": -10}
{"process_name": "nginx; rm -rf /", "cpu_percent": 12.5, "memory_mb": 256}
{"process_name": "nginx", "cpu_percent": 12.5}
{"process_name": "nginx", "memory_mb": 256}
This is not valid JSON
EOF

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
