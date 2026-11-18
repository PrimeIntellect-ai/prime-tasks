#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip strace
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/processor.py
import sys
import json

def load_settings():
    try:
        with open("/home/user/app/settings.json", "r") as f:
            return json.load(f)
    except Exception:
        sys.exit("Fatal error during startup.")

def calculate_variance(data):
    n = len(data)
    if n < 2:
        return 0.0
    sum_x = sum(data)
    sum_sq = sum(x*x for x in data)
    # Naive formula prone to catastrophic cancellation
    variance = (sum_sq - (sum_x * sum_x) / n) / (n - 1)
    return variance

def main():
    settings = load_settings()

    # Load data
    data = []
    with open("/home/user/app/data.csv", "r") as f:
        for line in f:
            if line.strip():
                data.append(float(line.strip()))

    var = calculate_variance(data)
    print(var)

if __name__ == "__main__":
    main()
EOF

    cat << 'EOF' > /home/user/app/data.csv
1000000001.0
1000000002.0
1000000003.0
1000000004.0
1000000005.0
EOF

    chmod -R 777 /home/user
