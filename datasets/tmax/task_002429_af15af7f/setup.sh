#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip espeak
pip3 install pytest

mkdir -p /app

# Generate the audio file using espeak
espeak -w /app/calibration_memo.wav "To fix the convergence instability, write a Python script that reads floats from standard input. Multiply the i-th element by the sine squared of pi times i over N minus one, where i is the zero-based index and N is the total number of elements. Compute the exact floating point sum of these windowed values using math dot fsum to avoid reduction order issues. Finally, multiply the sum by the calibration constant, which is 137.035999. Print the output to exactly eight decimal places."

# Create the oracle script
cat << 'EOF' > /app/oracle_process_signal.py
#!/usr/bin/env python3
import sys
import math

def main():
    lines = sys.stdin.read().split()
    if not lines:
        return
    floats = [float(x) for x in lines]
    N = len(floats)
    if N <= 1:
        print(f"{0.0:.8f}")
        return

    windowed = []
    for i, val in enumerate(floats):
        factor = math.sin(math.pi * i / (N - 1)) ** 2
        windowed.append(val * factor)

    total_sum = math.fsum(windowed)
    result = total_sum * 137.035999
    print(f"{result:.8f}")

if __name__ == "__main__":
    main()
EOF

chmod +x /app/oracle_process_signal.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
