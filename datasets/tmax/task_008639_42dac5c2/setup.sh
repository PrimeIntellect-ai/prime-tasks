#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip make
pip3 install pytest

mkdir -p /home/user/workspace/src
mkdir -p /home/user/workspace/data

# Create dummy data files. One file explicitly has only 1 line to trigger the ZeroDivisionError.
echo "10.5\n12.2\n11.8\n10.9" > /home/user/workspace/data/chunk_1.txt
echo "42.0" > /home/user/workspace/data/chunk_2.txt
echo "5.5\n6.1\n5.9" > /home/user/workspace/data/chunk_3.txt

# Create the buggy compute_stats.py
cat << 'EOF' > /home/user/workspace/src/compute_stats.py
import os
import glob

def calculate_variance(data):
    count = len(data)
    mean = sum(data) / count
    sum_sq = sum((x - mean) ** 2 for x in data)
    # Bug: ZeroDivisionError when count == 1
    return sum_sq / (count - 1)

def main():
    metrics_dir = os.environ.get("METRICS_DIR")
    if not metrics_dir or not os.path.exists(metrics_dir):
        raise FileNotFoundError(f"Metrics directory not found: {metrics_dir}")

    files = glob.glob(os.path.join(metrics_dir, "*.txt"))
    if not files:
        print("No data files found.")
        return

    for f in files:
        with open(f, 'r') as file:
            data = [float(line.strip()) for line in file if line.strip()]
            if data:
                var = calculate_variance(data)
                print(f"File: {os.path.basename(f)}, Variance: {var:.4f}")

if __name__ == "__main__":
    main()
EOF

touch /home/user/workspace/src/__init__.py

# Create the misconfigured Makefile
cat << 'EOF' > /home/user/workspace/Makefile
stats:
	METRICS_DIR=/invalid/path/data python3 src/compute_stats.py
EOF

useradd -m -s /bin/bash user || true
chown -R user:user /home/user/workspace
chmod -R 777 /home/user
