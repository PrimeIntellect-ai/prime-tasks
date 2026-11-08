#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > process_data.py
import math
import sys

def compute_population_stddev(data):
    n = len(data)
    if n == 0:
        return 0.0
    mean = sum(data) / n
    # Naive variance calculation, susceptible to catastrophic cancellation
    variance = sum([x**2 for x in data]) / n - mean**2
    return math.sqrt(variance)

def process_file(input_path, output_path):
    with open(input_path, 'r') as infile, open(output_path, 'w') as outfile:
        for line_num, line in enumerate(infile, 1):
            if not line.strip():
                continue
            data = [float(x) for x in line.split()]
            try:
                stddev = compute_population_stddev(data)
                outfile.write(f"{stddev}\n")
            except Exception as e:
                print(f"Error on line {line_num}: {e}")
                raise

if __name__ == "__main__":
    process_file("data_inputs.txt", "output.txt")
EOF

    python3 -c "
import random
random.seed(42)
with open('data_inputs.txt', 'w') as f:
    for i in range(1, 5001):
        # Insert the unstable line at line 3456
        if i == 3456:
            f.write('100000001.0 100000002.0 100000003.0 100000004.0 100000005.0\n')
        else:
            line = [str(round(random.uniform(0, 100), 2)) for _ in range(5)]
            f.write(' '.join(line) + '\n')
"

    chmod +x process_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
