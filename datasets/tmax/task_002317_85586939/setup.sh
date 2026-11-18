#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip strace
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/sensor_aggregator.py
import sys
import math

def load_data():
    with open("/home/user/sensor_data.txt", "r") as f:
        return [float(line.strip()) for line in f]

def chunk_data(data, size=10):
    chunks = []
    for i in range(0, len(data), size):
        chunk = data[i:i+size]
        if len(chunk) != size:
            # Fatal boundary condition bug
            raise ValueError("Fatal: Incomplete chunk detected. Corrupted data stream.")
        chunks.append(chunk)
    return chunks

def aggregate(chunks):
    total = 0.0
    for chunk in chunks:
        for val in chunk:
            # Precision loss occurs here due to naive float addition
            total += val
    return total

def main():
    # Silent failure to test system call tracing (strace)
    try:
        with open("/home/user/config/settings.json", "r") as f:
            pass
    except Exception:
        sys.exit(1)

    data = load_data()
    chunks = chunk_data(data)
    result = aggregate(chunks)

    with open("/home/user/output.txt", "w") as f:
        f.write(f"{result:.2f}\n")

if __name__ == "__main__":
    main()
EOF

    cat << 'EOF' > /home/user/sensor_data.txt
1e16
EOF
    for i in $(seq 1 103); do
        echo "1.5" >> /home/user/sensor_data.txt
    done
    echo "-1e16" >> /home/user/sensor_data.txt

    chmod +x /home/user/sensor_aggregator.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
