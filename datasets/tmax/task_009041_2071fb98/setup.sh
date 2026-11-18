#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/forensics

    cat << 'EOF' > /home/user/forensics/log_analyzer.py
import sys
import random
import argparse

def generate_data(seed):
    random.seed(seed)
    # Generate random number of data points between 95 and 105
    # This ensures that sometimes it's not a multiple of 10, causing the chunking bug
    num_points = random.randint(95, 105)
    return [random.gauss(40, 10) if random.random() < 0.5 else random.gauss(80, 10) for _ in range(num_points)]

def process_chunks(data, chunk_size=10):
    chunks = []
    # Bug 1: IndexError when len(data) is not a multiple of chunk_size
    for i in range(0, len(data), chunk_size):
        chunk = [data[i+j] for j in range(chunk_size)] 
        chunks.append(chunk)
    return chunks

def find_threshold(data):
    threshold = sum(data) / len(data)
    for _ in range(100):
        low = [x for x in data if x <= threshold]
        high = [x for x in data if x > threshold]

        if not low or not high:
            break

        new_threshold = (sum(low)/len(low) + sum(high)/len(high)) / 2.0

        # Bug 2: Missing absolute value for convergence check
        if new_threshold - threshold < 0.001: 
            break

        threshold = new_threshold
    else:
        raise ValueError("Convergence failed")

    return threshold

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", type=int, required=True)
    args = parser.parse_args()

    data = generate_data(args.seed)

    # Process chunks (this will crash on certain seeds)
    chunks = process_chunks(data)

    # Flatten back for thresholding
    flat_data = [item for sublist in chunks for item in sublist]

    # Find threshold (this will fail to converge due to bug)
    thresh = find_threshold(flat_data)

    print(f"Seed {args.seed}: {thresh:.2f}")

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
