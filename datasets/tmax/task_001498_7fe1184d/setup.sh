#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    mkdir -p /app

    # Generate the audio instructions
    espeak -w /app/instructions.wav "Hello. Please write a Python script at slash home slash user slash process dot py. It must read space-separated numbers from standard input. First, calculate the Gaussian kernel density estimate at x equals zero with a bandwidth of one point two five. Second, compute the ninety five percent confidence interval of the mean using a normal approximation, meaning one point nine six times the sample standard deviation over the square root of N. Use the sample standard deviation with delta degrees of freedom equal to one. Output the KDE at zero, the CI lower bound, and the CI upper bound, separated by commas, each rounded to exactly four decimal places. Thank you."

    # Create the oracle script
    cat << 'EOF' > /app/oracle.py
#!/usr/bin/env python3
import sys
import math

def main():
    data = sys.stdin.read().split()
    if not data:
        return
    nums = [float(x) for x in data]
    n = len(nums)
    if n < 2:
        return

    # KDE at x=0, h=1.25
    h = 1.25
    kde_sum = 0.0
    for x in nums:
        z = (0.0 - x) / h
        kde_sum += math.exp(-0.5 * z**2) / math.sqrt(2 * math.pi)
    kde = kde_sum / (n * h)

    # CI using normal approx
    mean = sum(nums) / n
    variance = sum((x - mean)**2 for x in nums) / (n - 1)
    std_dev = math.sqrt(variance)

    margin = 1.96 * std_dev / math.sqrt(n)
    ci_lower = mean - margin
    ci_upper = mean + margin

    print(f"{kde:.4f},{ci_lower:.4f},{ci_upper:.4f}")

if __name__ == "__main__":
    main()
EOF
    chmod +x /app/oracle.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
